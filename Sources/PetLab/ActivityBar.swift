import AppKit
import PetCore

private final class BarButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The card's body: a plain click does nothing, a drag moves the cat, a right-click opens the card menu.
private final class CardView: NSVisualEffectView {
    weak var petView: PetView?
    var onMenu: ((NSEvent) -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) { petView?.beginDrag() }
    override func mouseDragged(with event: NSEvent) { petView?.continueDrag() }
    override func mouseUp(with event: NSEvent) { petView?.endDrag() }
    override func rightMouseDown(with event: NSEvent) { onMenu?(event) }
}

final class ActivityBar: NSObject {
    static let height: CGFloat = 54
    static let gap: CGFloat = 4
    let panel: NSPanel
    private let titleLabel = NSTextField(labelWithString: "No sessions running")
    private let detailLabel = NSTextField(labelWithString: "Watching Claude")
    private let dot = NSView()
    private let chevronButton = BarButton()
    private let openButton = BarButton()
    private let card = CardView()
    private var sessions: [MonitorSnapshot.Session] = []
    private var selectedKey: String?
    private var followsActivity = true
    private var healthy = true
    private var fingerprint = ""
    /// Set for a cat that follows one session; adds "Close this cat" to the dropdown.
    var onClose: (() -> Void)?

    init(parent: NSPanel) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: Self.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = "Pet Lab activity"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let background = card
        background.frame = NSRect(origin: .zero, size: panel.frame.size)
        background.material = .hudWindow; background.blendingMode = .behindWindow; background.state = .active
        background.appearance = NSAppearance(named: .darkAqua)
        background.wantsLayer = true; background.layer?.cornerRadius = 12; background.layer?.masksToBounds = true
        background.petView = parent.contentView as? PetView
        background.onMenu = { [weak self] event in self?.showCardMenu(event) }
        panel.contentView = background
        dot.frame = NSRect(x: 12, y: 30, width: 7, height: 7)
        dot.wantsLayer = true; dot.layer?.cornerRadius = 3.5
        background.addSubview(dot)
        titleLabel.frame = NSRect(x: 27, y: 24, width: 214, height: 19)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .white; titleLabel.lineBreakMode = .byTruncatingTail; titleLabel.maximumNumberOfLines = 1
        titleLabel.setAccessibilityLabel("Session title")
        detailLabel.frame = NSRect(x: 27, y: 7, width: 214, height: 16)
        detailLabel.font = .systemFont(ofSize: 10); detailLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        detailLabel.lineBreakMode = .byTruncatingTail
        background.addSubview(titleLabel); background.addSubview(detailLabel)
        // Right column: the session picker lines up with the title, the open button with the detail line.
        let small = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        chevronButton.frame = NSRect(x: 248, y: 23.5, width: 22, height: 20)
        configure(chevronButton, symbol: "chevron.down", configuration: small, label: "Choose session",
                  tip: "Switch to another Claude session", action: #selector(showSessions))
        openButton.frame = NSRect(x: 248, y: 5, width: 22, height: 20)
        configure(openButton, symbol: "arrow.up.right", configuration: small, label: "Open session",
                  tip: "Open this session", action: #selector(openSelected))
        background.addSubview(chevronButton); background.addSubview(openButton)
        parent.addChildWindow(panel, ordered: .above)
        panel.orderFrontRegardless()
    }

    private func configure(_ button: NSButton, symbol: String, configuration: NSImage.SymbolConfiguration,
                           label: String, tip: String, action: Selector) {
        button.bezelStyle = .regularSquare; button.isBordered = false; button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?.withSymbolConfiguration(configuration)
        button.contentTintColor = .white; button.title = ""
        button.target = self; button.action = action
        button.setAccessibilityLabel(label); button.toolTip = tip
    }

    func update(snapshot: MonitorSnapshot?, healthy: Bool, parent: NSPanel, emptySpaceAbove: CGFloat = 0) {
        sessions = snapshot?.sessions ?? []; self.healthy = healthy
        if followsActivity || !sessions.contains(where: { $0.key == selectedKey }) {
            selectedKey = snapshot?.preferredSession?.key; followsActivity = true
        }
        let selected = sessions.first(where: { $0.key == selectedKey })
        let canOpen = selected.map(SessionOpener.canOpen) ?? false
        if openButton.isHidden == canOpen { openButton.isHidden = !canOpen }
        openButton.toolTip = selected?.appURL != nil ? "Open this session in the Claude app" : "Show this session's terminal"
        let title = selected?.title?.isEmpty == false ? selected!.title! : selected == nil ? "No sessions running" : "Claude session"
        let activity = healthy ? selected?.activity ?? .idle : .uncertain
        let status = Self.label(activity)
        let workingCount = sessions.filter { $0.activity == .working }.count
        let waitingCount = sessions.filter { $0.activity == .attention }.count
        let counts = (waitingCount > 0 ? ["\(waitingCount) waiting"] : [])
            + (workingCount > 0 ? ["\(workingCount) working"] : [])
        let summary = counts.isEmpty ? "\(sessions.count) session\(sessions.count == 1 ? "" : "s")" : counts.joined(separator: " · ")
        let detail = healthy ? "Claude · \(status) · \(summary)" : "Checking session status…"
        let next = title + detail
        if fingerprint != next {
            titleLabel.stringValue = title; titleLabel.toolTip = title
            detailLabel.stringValue = detail
            dot.layer?.backgroundColor = (activity == .working ? NSColor.systemGreen : activity == .attention ? .systemOrange : .systemGray).cgColor
            fingerprint = next
        }
        let screen = parent.screen ?? NSScreen.main
        if let screen {
            let suggested = NSRect(x: parent.frame.midX-panel.frame.width/2, y: parent.frame.maxY-emptySpaceAbove+Self.gap,
                                   width: panel.frame.width, height: panel.frame.height)
            let frame = DesktopGeometry.clamp(suggested, to: screen.visibleFrame)
            if panel.frame.origin != frame.origin { panel.setFrameOrigin(frame.origin) }
        }
    }

    static func label(_ activity: Activity) -> String {
        switch activity {
        case .working: return "Working"
        case .attention: return "Needs input"
        case .uncertain: return "Status unknown"
        case .failed: return "Failed"
        case .completed: return "Ready"
        case .interrupted: return "Interrupted"
        case .retired: return "Ended"
        case .idle: return "Idle"
        }
    }

    @objc private func showSessions() {
        let menu = NSMenu()
        let automatic = menu.addItem(withTitle: "Follow active session", action: #selector(followActivity), keyEquivalent: "")
        automatic.target = self; automatic.state = followsActivity ? .on : .off
        menu.addItem(.separator())
        if sessions.isEmpty { menu.addItem(withTitle: "No sessions running", action: nil, keyEquivalent: "") }
        for session in sessions {
            let title = session.title?.isEmpty == false ? session.title! : "Claude session"
            let item = menu.addItem(withTitle: "\(title) — \(healthy ? Self.label(session.activity) : "Status unknown")", action: #selector(selectSession(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = session.key
            item.state = !followsActivity && selectedKey == session.key ? .on : .off
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -2), in: chevronButton)
    }
    private func showCardMenu(_ event: NSEvent) {
        let menu = NSMenu()
        if let selected = sessions.first(where: { $0.key == selectedKey }), SessionOpener.canOpen(selected) {
            let open = menu.addItem(withTitle: selected.appURL != nil ? "Open in Claude" : "Show terminal", action: #selector(openSelected), keyEquivalent: "")
            open.target = self
        }
        if onClose != nil {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            let close = menu.addItem(withTitle: "Close this cat", action: #selector(closeCat), keyEquivalent: "")
            close.target = self
            close.toolTip = "Hide this cat until its session ends or you bring it back from the menu bar"
        }
        guard !menu.items.isEmpty else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: card)
    }
    @objc private func closeCat() { onClose?() }
    @objc private func openSelected() {
        guard let selected = sessions.first(where: { $0.key == selectedKey }) else { return }
        SessionOpener.open(selected)
    }
    @objc private func followActivity() { followsActivity = true }
    @objc private func selectSession(_ item: NSMenuItem) { selectedKey = item.representedObject as? String; followsActivity = false }

    func capture(to url: URL) throws {
        guard let content = panel.contentView, let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) { try data.write(to: url) }
    }
}

/// Brings a tracked session forward: the Claude desktop app's Code tab via its deep link, or the
/// app (Terminal, iTerm, an editor…) that hosts a CLI session's process — on its exact tab in
/// Terminal and iTerm2, matched by the session's tty.
enum SessionOpener {
    static func canOpen(_ session: MonitorSnapshot.Session) -> Bool { session.appURL != nil || session.pid != nil }

    static func open(_ session: MonitorSnapshot.Session) {
        if let url = session.appURL { NSWorkspace.shared.open(url); return }
        guard let pid = session.pid, let app = hostApp(of: pid) else { return }
        app.unhide()
        guard let tty = terminalDevice(of: pid), let script = tabScript(for: app.bundleIdentifier) else { app.activate(); return }
        // osascript keeps the main thread free while macOS asks for Automation permission the first time.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, "/dev/" + tty]
        let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            let result = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Denied permission or no matching tab: still bring the app forward.
            if finished.terminationStatus != 0 || result != "ok" { DispatchQueue.main.async { app.activate() } }
        }
        do { try process.run() } catch { app.activate() }
    }

    /// Selects the tab whose tty matches, raises only its window, then activates the app.
    static func tabScript(for bundleID: String?) -> String? {
        switch bundleID {
        case "com.apple.Terminal":
            return """
            on run argv
              set target to item 1 of argv
              tell application id "com.apple.Terminal"
                repeat with w in windows
                  repeat with t in tabs of w
                    if tty of t is target then
                      set selected of t to true
                      set index of w to 1
                      activate
                      return "ok"
                    end if
                  end repeat
                end repeat
              end tell
              return "missing"
            end run
            """
        case "com.googlecode.iterm2":
            return """
            on run argv
              set target to item 1 of argv
              tell application id "com.googlecode.iterm2"
                repeat with w in windows
                  repeat with t in tabs of w
                    repeat with s in sessions of t
                      if tty of s is target then
                        select w
                        select t
                        select s
                        activate
                        return "ok"
                      end if
                    end repeat
                  end repeat
                end repeat
              end tell
              return "missing"
            end run
            """
        default: return nil
        }
    }

    /// The controlling terminal's device name (e.g. "ttys004"), or nil when the process has none.
    static func terminalDevice(of pid: pid_t) -> String? {
        guard let info = processInfo(pid), info.kp_eproc.e_tdev != -1, let name = devname(info.kp_eproc.e_tdev, S_IFCHR) else { return nil }
        let device = String(cString: name)
        return device.hasPrefix("tty") ? device : nil
    }

    /// Walks up the process tree to the first ancestor that is a regular, Dock-visible app.
    static func hostApp(of pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<32 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular { return app }
            guard let parent = parentPID(of: current), parent > 1, parent != current else { return nil }
            current = parent
        }
        return nil
    }

    private static func parentPID(of pid: pid_t) -> pid_t? { processInfo(pid)?.kp_eproc.e_ppid }

    private static func processInfo(_ pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }
}
