import AppKit
import PetCore

private final class BarButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class ActivityBar: NSObject {
    static let height: CGFloat = 54
    static let gap: CGFloat = 6
    let panel: NSPanel
    private let titleLabel = NSTextField(labelWithString: "No sessions running")
    private let detailLabel = NSTextField(labelWithString: "Watching Claude")
    private let dot = NSView()
    private let button = BarButton()
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
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: panel.frame.size))
        background.material = .hudWindow; background.blendingMode = .behindWindow; background.state = .active
        background.appearance = NSAppearance(named: .darkAqua)
        background.wantsLayer = true; background.layer?.cornerRadius = 12; background.layer?.masksToBounds = true
        panel.contentView = background
        dot.frame = NSRect(x: 12, y: 32, width: 7, height: 7)
        dot.wantsLayer = true; dot.layer?.cornerRadius = 3.5
        background.addSubview(dot)
        titleLabel.frame = NSRect(x: 27, y: 24, width: 220, height: 19)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .white; titleLabel.lineBreakMode = .byTruncatingTail; titleLabel.maximumNumberOfLines = 1
        titleLabel.setAccessibilityLabel("Session title")
        detailLabel.frame = NSRect(x: 27, y: 7, width: 225, height: 16)
        detailLabel.font = .systemFont(ofSize: 10); detailLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        detailLabel.lineBreakMode = .byTruncatingTail
        background.addSubview(titleLabel); background.addSubview(detailLabel)
        let chevron = NSImageView(frame: NSRect(x: 254, y: 19, width: 12, height: 12))
        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        chevron.contentTintColor = .white; background.addSubview(chevron)
        button.frame = background.bounds; button.isBordered = false; button.isTransparent = true
        button.title = ""; button.target = self; button.action = #selector(showSessions)
        button.setAccessibilityLabel("Choose session")
        button.toolTip = "Show tracked Claude sessions"
        background.addSubview(button)
        parent.addChildWindow(panel, ordered: .above)
        panel.orderFrontRegardless()
    }

    func update(snapshot: MonitorSnapshot?, healthy: Bool, parent: NSPanel) {
        sessions = snapshot?.sessions ?? []; self.healthy = healthy
        if followsActivity || !sessions.contains(where: { $0.key == selectedKey }) {
            selectedKey = snapshot?.preferredSession?.key; followsActivity = true
        }
        let selected = sessions.first(where: { $0.key == selectedKey })
        let title = selected?.title?.isEmpty == false ? selected!.title! : selected == nil ? "No sessions running" : "Claude session"
        let activity = healthy ? selected?.activity ?? .idle : .uncertain
        let status = Self.label(activity)
        let workingCount = sessions.filter { $0.activity == .working }.count
        let summary = workingCount > 0 ? "\(workingCount) working" : "\(sessions.count) session\(sessions.count == 1 ? "" : "s")"
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
            let suggested = NSRect(x: parent.frame.midX-panel.frame.width/2, y: parent.frame.maxY+Self.gap,
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
        if onClose != nil {
            menu.addItem(.separator())
            let close = menu.addItem(withTitle: "Close this cat", action: #selector(closeCat), keyEquivalent: "")
            close.target = self
            close.toolTip = "Hide this cat until its session ends or you bring it back from the menu bar"
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -2), in: button)
    }
    @objc private func closeCat() { onClose?() }
    @objc private func followActivity() { followsActivity = true }
    @objc private func selectSession(_ item: NSMenuItem) { selectedKey = item.representedObject as? String; followsActivity = false }

    func capture(to url: URL) throws {
        guard let content = panel.contentView, let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) { try data.write(to: url) }
    }
}
