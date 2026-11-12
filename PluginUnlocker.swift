import AppKit

// PluginUnlocker — a menu bar app that removes the macOS quarantine flag
// from audio plugins you build yourself, so Gatekeeper stops blocking them.
// It only ever touches the folders you tell it to watch, and only strips the
// "com.apple.quarantine" attribute (plus an ad-hoc local signature). It never
// changes any system-wide Gatekeeper setting.

final class Controller: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let defaults = UserDefaults.standard
    var watchers: [DirWatcher] = []
    var lastAction = "Esperando plugins nuevos…"
    var debounceWork: DispatchWorkItem?

    var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled"); refresh() }
    }

    var folders: [String] {
        get {
            if let saved = defaults.array(forKey: "folders") as? [String], !saved.isEmpty { return saved }
            let home = NSHomeDirectory()
            return [
                "\(home)/Library/Audio/Plug-Ins/VST3",
                "\(home)/Library/Audio/Plug-Ins/Components",
                "\(home)/Library/Audio/Plug-Ins/VST",
            ]
        }
        set { defaults.set(newValue, forKey: "folders"); restartWatching() }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bolt.shield", accessibilityDescription: "Plugin Unlocker")
        }
        rebuildMenu()
        restartWatching()
        scanAll()
    }

    // MARK: watching

    func restartWatching() {
        watchers.forEach { $0.stop() }
        watchers = folders.compactMap { path in
            DirWatcher(path: path) { [weak self] in self?.scheduleScan() }
        }
    }

    func scheduleScan() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scanAll() }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func scanAll() {
        guard enabled else { return }
        for folder in folders { scan(folder) }
    }

    func scan(_ folder: String) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: folder) else { return }
        let exts: Set<String> = ["vst3", "component", "vst", "app"]
        for item in items where exts.contains((item as NSString).pathExtension) {
            let full = "\(folder)/\(item)"
            if hasQuarantine(full) {
                clean(full)
                lastAction = "Destrabado: \(item)"
                flash(item)
                rebuildMenu()
            }
        }
    }

    // MARK: actions

    func hasQuarantine(_ path: String) -> Bool {
        run("/usr/bin/xattr", ["-p", "com.apple.quarantine", path], capture: true).status == 0
    }

    func clean(_ path: String) {
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", path])
        _ = run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", path])
    }

    @discardableResult
    func run(_ launch: String, _ args: [String], capture: Bool = false) -> (status: Int32, _ unused: Bool) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        if capture { p.standardOutput = Pipe(); p.standardError = Pipe() }
        do { try p.run() } catch { return (-1, false) }
        p.waitUntilExit()
        return (p.terminationStatus, false)
    }

    func flash(_ name: String) {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "checkmark.shield.fill", accessibilityDescription: "Listo")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            button.image = NSImage(systemSymbolName: "bolt.shield", accessibilityDescription: "Plugin Unlocker")
            _ = self
        }
    }

    // MARK: menu

    func refresh() { rebuildMenu() }

    func rebuildMenu() {
        let menu = NSMenu()

        let status = NSMenuItem(title: enabled ? "Activo" : "Pausado", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let last = NSMenuItem(title: lastAction, action: nil, keyEquivalent: "")
        last.isEnabled = false
        menu.addItem(last)

        menu.addItem(.separator())

        let toggle = NSMenuItem(title: enabled ? "Pausar" : "Reanudar",
                                action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let now = NSMenuItem(title: "Revisar ahora", action: #selector(cleanNow), keyEquivalent: "r")
        now.target = self
        menu.addItem(now)

        menu.addItem(.separator())

        let header = NSMenuItem(title: "Carpetas vigiladas", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for folder in folders {
            let short = (folder as NSString).abbreviatingWithTildeInPath
            let exists = FileManager.default.fileExists(atPath: folder)
            let item = NSMenuItem(title: (exists ? "  " : "  ⚠︎ ") + short,
                                  action: #selector(removeFolder(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = folder
            item.toolTip = "Clic para dejar de vigilar"
            menu.addItem(item)
        }

        let add = NSMenuItem(title: "Agregar carpeta…", action: #selector(addFolder), keyEquivalent: "")
        add.target = self
        menu.addItem(add)

        let reset = NSMenuItem(title: "Volver a las carpetas por defecto", action: #selector(resetFolders), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Salir", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc func toggleEnabled() { enabled.toggle(); if enabled { scanAll() } }
    @objc func cleanNow() { let was = enabled; if !was { } ; for f in folders { scan(f) }; rebuildMenu() }

    @objc func addFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Vigilar"
        if panel.runModal() == .OK, let url = panel.url {
            var f = folders
            if !f.contains(url.path) { f.append(url.path); folders = f }
            rebuildMenu()
        }
    }

    @objc func removeFolder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        folders = folders.filter { $0 != path }
        rebuildMenu()
    }

    @objc func resetFolders() {
        defaults.removeObject(forKey: "folders")
        restartWatching()
        rebuildMenu()
    }

    @objc func quit() { NSApp.terminate(nil) }
}

// MARK: - Directory watcher (fires when a folder's contents change)

final class DirWatcher {
    private var fd: Int32 = -1
    private var source: DispatchSourceFileSystemObject?

    init?(path: String, onChange: @escaping () -> Void) {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename], queue: .main)
        src.setEventHandler { onChange() }
        src.setCancelHandler { [fd] in close(fd) }
        source = src
        src.resume()
    }

    func stop() { source?.cancel(); source = nil }
    deinit { stop() }
}

let app = NSApplication.shared
let controller = Controller()
app.delegate = controller
app.run()
