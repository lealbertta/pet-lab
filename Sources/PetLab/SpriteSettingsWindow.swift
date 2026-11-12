import AppKit
import PetCore

final class SpriteSettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private var preferences: PetPreferences
    private let onChange: ([String]) throws -> Void
    private var sprites: [(id: String, name: String)] = []
    private var loadError: String?
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private let enable = NSButton(title: "Enable selected", target: nil, action: nil)
    private let disable = NSButton(title: "Disable selected", target: nil, action: nil)

    init(packsURL: URL, preferences: PetPreferences, onChange: @escaping ([String]) throws -> Void) {
        self.preferences = preferences; self.onChange = onChange
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Sprites"; window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 400)
        super.init(window: window)
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: packsURL, includingPropertiesForKeys: nil)
            sprites = try urls.filter { $0.lastPathComponent.range(of: "^cat-[0-9]{2}-[a-z-]+$", options: .regularExpression) != nil }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }.map { url in
                    let manifest = try JSONDecoder().decode(PackManifest.self, from: Data(contentsOf: url.appendingPathComponent("manifest.json")))
                    return (url.lastPathComponent, manifest.name)
                }
        } catch {
            loadError = "Couldn’t load the sprite library. Restart Pet Lab to retry."
        }
        let body = NSStackView(); body.orientation = .vertical; body.alignment = .leading; body.spacing = 14
        body.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            body.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            body.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            body.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -24)
        ])
        let title = NSTextField(labelWithString: "Choose your sprites")
        title.font = .systemFont(ofSize: 23, weight: .bold); body.addArrangedSubview(title)
        let detail = NSTextField(wrappingLabelWithString: "Choose which cats Multicats can use. Changes apply to active sessions. Disabling every sprite hides Multicats pets.")
        detail.textColor = .secondaryLabelColor; body.addArrangedSubview(detail)
        let hint = NSTextField(labelWithString: "⌘-click or Shift-click to select multiple sprites.")
        hint.font = .systemFont(ofSize: 12); body.addArrangedSubview(hint)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sprite"))
        column.title = "Available sprites"; column.width = 480
        table.addTableColumn(column); table.headerView = nil
        table.allowsMultipleSelection = true; table.rowHeight = 34
        table.dataSource = self; table.delegate = self
        table.setAccessibilityLabel("Sprite availability")
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder; body.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        let selectAll = NSButton(title: "Select all", target: self, action: #selector(selectAllRows))
        enable.target = self; enable.action = #selector(enableSelected)
        disable.target = self; disable.action = #selector(disableSelected)
        let actions = NSStackView(views: [selectAll, enable, disable]); actions.spacing = 8
        for button in [selectAll, enable, disable] { button.bezelStyle = .rounded }
        body.addArrangedSubview(actions)
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
        body.addArrangedSubview(status)
        refresh(preferences); window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func numberOfRows(in tableView: NSTableView) -> Int { sprites.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let button = NSButton(checkboxWithTitle: sprites[row].name, target: self, action: #selector(toggle(_:)))
        button.tag = row; button.state = preferences.disabledSprites.contains(sprites[row].id) ? .off : .on
        button.toolTip = "Allow \(sprites[row].name) in Multicats"
        return button
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }
    private func updateButtons() {
        enable.isEnabled = table.numberOfSelectedRows > 0; disable.isEnabled = table.numberOfSelectedRows > 0
    }
    func refresh(_ value: PetPreferences) {
        preferences = value
        let selection = table.selectedRowIndexes
        table.reloadData(); table.selectRowIndexes(selection, byExtendingSelection: false); updateButtons()
        let count = sprites.filter { !value.disabledSprites.contains($0.id) }.count
        status.stringValue = loadError ?? (sprites.isEmpty ? "No sprites available." : "\(count) of \(sprites.count) enabled · Saved automatically")
    }
    private func setEnabled(_ enabled: Bool, rows: IndexSet) {
        var disabled = Set(preferences.disabledSprites)
        for row in rows {
            if enabled { disabled.remove(sprites[row].id) } else { disabled.insert(sprites[row].id) }
        }
        do {
            try onChange(disabled.sorted())
            var value = preferences; value.disabledSprites = disabled.sorted(); refresh(value)
            status.textColor = .secondaryLabelColor
        } catch {
            refresh(preferences)
            status.stringValue = "Couldn’t save changes. Please try again."; status.textColor = .systemRed
        }
    }
    @objc private func toggle(_ sender: NSButton) { setEnabled(sender.state == .on, rows: IndexSet(integer: sender.tag)) }
    @objc private func selectAllRows() { table.selectAll(nil) }
    @objc private func enableSelected() { setEnabled(true, rows: table.selectedRowIndexes) }
    @objc private func disableSelected() { setEnabled(false, rows: table.selectedRowIndexes) }
    func present() { showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
}
