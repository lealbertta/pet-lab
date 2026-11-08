import AppKit
import SpriteKit
import PetCore

final class SettingsWindowController: NSWindowController {
    private var preferences: PetPreferences
    private let onChange: (PetPreferences) throws -> Void
    private let slider = NSSlider(value: 100, minValue: 50, maxValue: 200, target: nil, action: nil)
    private let percentage = NSTextField(labelWithString: "100%")
    private let wandering = NSButton(checkboxWithTitle: "Allow idle wandering", target: nil, action: nil)
    private let labels = NSButton(checkboxWithTitle: "Show session labels above pets", target: nil, action: nil)
    private let multicatsToggle = NSButton(checkboxWithTitle: "Multicats mode — one cat per session", target: nil, action: nil)
    private var effectiveMulticats: Bool
    private let status = NSTextField(labelWithString: "Changes are saved automatically.")
    private let previewNode = SKSpriteNode()

    init(preferences: PetPreferences, multicats: Bool, textures: [SKTexture], durations: [TimeInterval], onChange: @escaping (PetPreferences) throws -> Void) {
        self.preferences = preferences; self.onChange = onChange; self.effectiveMulticats = multicats
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 650),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Pet Lab Settings"; window.isReleasedWhenClosed = false
        super.init(window: window)
        let body = NSStackView(); body.orientation = .vertical; body.alignment = .leading; body.spacing = 18
        body.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(body)
        NSLayoutConstraint.activate([body.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            body.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            body.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)])
        let title = NSTextField(labelWithString: "Make room for your companions")
        title.font = .systemFont(ofSize: 23, weight: .bold)
        body.addArrangedSubview(title)
        let subtitle = NSTextField(labelWithString: "Personalize every pet. Changes appear immediately.")
        subtitle.textColor = .secondaryLabelColor; subtitle.font = .systemFont(ofSize: 13)
        body.addArrangedSubview(subtitle)

        let preview = SKView(); preview.translatesAutoresizingMaskIntoConstraints = false
        preview.wantsLayer = true; preview.layer?.cornerRadius = 16; preview.layer?.masksToBounds = true
        preview.setAccessibilityLabel("Animated pet size preview")
        let scene = SKScene(size: CGSize(width: 504, height: 190))
        scene.backgroundColor = NSColor(red: 0.97, green: 0.94, blue: 0.88, alpha: 1)
        scene.scaleMode = .resizeFill
        previewNode.position = CGPoint(x: 252, y: 90); scene.addChild(previewNode)
        if let texture = textures.first {
            previewNode.texture = texture
            let actions = textures.enumerated().map { index, texture in
                SKAction.sequence([.setTexture(texture), .wait(forDuration: durations[index])])
            }
            previewNode.run(.repeatForever(.sequence(actions)))
        }
        preview.presentScene(scene); preview.preferredFramesPerSecond = 20
        body.addArrangedSubview(preview)
        NSLayoutConstraint.activate([preview.widthAnchor.constraint(equalTo: body.widthAnchor), preview.heightAnchor.constraint(equalToConstant: 190)])

        let sizeTitle = NSTextField(labelWithString: "Pet size")
        sizeTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        percentage.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        let sizeRow = NSStackView(views: [sizeTitle, NSView(), percentage]); sizeRow.distribution = .fill
        body.addArrangedSubview(sizeRow); sizeRow.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        slider.target = self; slider.action = #selector(sizeChanged); slider.isContinuous = true
        slider.setAccessibilityLabel("Pet size"); slider.toolTip = "Resize every pet from 50% to 200%"
        body.addArrangedSubview(slider); slider.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        let presets = NSStackView(); presets.spacing = 10
        for (name, value) in [("Small", 75), ("Default", 100), ("Large", 150)] {
            let button = NSButton(title: name, target: self, action: #selector(preset(_:)))
            button.bezelStyle = .rounded; button.tag = value; presets.addArrangedSubview(button)
        }
        body.addArrangedSubview(presets)
        multicatsToggle.target = self; multicatsToggle.action = #selector(modeChanged)
        multicatsToggle.toolTip = "Assign a different random cat to each Claude session, choosing unused cats first"
        body.addArrangedSubview(multicatsToggle)
        wandering.target = self; wandering.action = #selector(behaviorChanged)
        labels.target = self; labels.action = #selector(behaviorChanged)
        body.addArrangedSubview(wandering); body.addArrangedSubview(labels)
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        body.addArrangedSubview(status)
        refresh(preferences, multicats: multicats)
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refresh(_ value: PetPreferences, multicats: Bool) {
        effectiveMulticats = value.multicats ?? multicats
        preferences = value; slider.doubleValue = value.sizeScale*100
        percentage.stringValue = "\(Int(value.sizeScale*100))%"
        wandering.state = value.allowWandering ? .on : .off
        labels.state = value.showSessionLabels ? .on : .off
        multicatsToggle.state = effectiveMulticats ? .on : .off
        let ratio = previewNode.texture.map { $0.size().width/$0.size().height } ?? 1
        previewNode.size = CGSize(width: 82*value.sizeScale*ratio, height: 82*value.sizeScale)
    }
    private func commit(_ value: PetPreferences) {
        do {
            try onChange(value); refresh(value, multicats: effectiveMulticats)
            status.stringValue = "Changes are saved automatically."; status.textColor = .secondaryLabelColor
        } catch {
            status.stringValue = "Couldn’t save settings. Please try again."; status.textColor = .systemRed
        }
    }
    @objc private func sizeChanged() {
        var value = preferences; value.sizeScale = (slider.doubleValue/5).rounded()*5/100; commit(value)
    }
    @objc private func preset(_ sender: NSButton) {
        var value = preferences; value.sizeScale = Double(sender.tag)/100; commit(value)
    }
    @objc private func behaviorChanged() {
        var value = preferences; value.allowWandering = wandering.state == .on; value.showSessionLabels = labels.state == .on; commit(value)
    }
    @objc private func modeChanged() {
        var value = preferences; value.multicats = multicatsToggle.state == .on; commit(value)
    }
    func present() {
        showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func capture(to url: URL) throws {
        guard let content = window?.contentView, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) { try data.write(to: url) }
    }
}
