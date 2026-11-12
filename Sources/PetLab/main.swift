import AppKit
import SpriteKit
import ImageIO
import PetCore
import Darwin

func json(_ object: Any) {
    if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) { print(text); fflush(stdout) }
}

let arguments = Array(CommandLine.arguments.dropFirst())
/// Pack frames last at least 110 ms (~9 fps) and roaming moves 22 pt/s, so 15 fps keeps timing
/// and walking smooth while halving the redraw and update work of the old 30 fps loop.
let petFramesPerSecond = 15
func option(_ name: String, fallback: String) -> String {
    guard let i = arguments.firstIndex(of: name), arguments.indices.contains(i+1) else { return fallback }
    return arguments[i+1]
}
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let bundledPack = Bundle.main.resourceURL?.appendingPathComponent("packs/starter")
let defaultPack = bundledPack.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    ?? root.appendingPathComponent("packs/starter")
let packURL = URL(fileURLWithPath: option("--pack", fallback: defaultPack.path))
let preferencesURL = URL(fileURLWithPath: option("--preferences-file", fallback:
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Pet Lab/preferences.json").path))

extension NSScreen {
    /// Visible frame with an auto-hidden Dock's reserved strip given back, so pets reach the bottom edge.
    var standingFrame: CGRect { DesktopGeometry.standingArea(screen: frame, visible: visibleFrame) }
}

final class PetView: SKView {
    var topAccessoryHeight: CGFloat = 0
    /// Height of the pet's feet above the bottom of the window (transparent padding below them).
    var footInset: CGFloat = 0
    var onMenu: (() -> Void)?
    var onDrag: (() -> Void)?
    var onClick: (() -> Void)?
    private var mouseDownPoint: NSPoint?
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { beginDrag() }
    override func mouseDragged(with event: NSEvent) { continueDrag() }
    override func mouseUp(with event: NSEvent) { if event.clickCount > 0 { onClick?() }; endDrag() }
    /// Drag entry points, shared with the session card above the cat so either one moves it.
    func beginDrag() { mouseDownPoint = NSEvent.mouseLocation }
    func endDrag() { mouseDownPoint = nil }
    func continueDrag() {
        guard let window = window, let previous = mouseDownPoint else { return }
        let current = NSEvent.mouseLocation
        let proposed = NSRect(x: window.frame.minX + current.x-previous.x,
                              y: window.frame.minY + current.y-previous.y,
                              width: window.frame.width, height: window.frame.height)
        let screens = NSScreen.screens.map(\.frame)
        if let bounds = NSScreen.screens.first(where: { $0.frame.contains(current) })?.frame
            ?? DesktopGeometry.containingScreen(for: proposed, screens: screens) {
            let visible = NSScreen.screens.first(where: { $0.frame == bounds })?.standingFrame ?? bounds
            window.setFrame(DesktopGeometry.clamp(proposed, to: DesktopGeometry.petBounds(on: visible, accessoryHeight: topAccessoryHeight, footInset: footInset)), display: true)
        }
        mouseDownPoint = current; onDrag?()
    }
    override func rightMouseDown(with event: NSEvent) { onMenu?() }
}

final class PetWindow {
    let panel: NSPanel
    let view: PetView
    let scene: SKScene
    let node: SKSpriteNode
    let label: SKLabelNode
    var activityBar: ActivityBar?
    var animationName = ""
    var roamingMotion: RoamingMotion?
    var idleRoaming: IdleRoaming?
    var roaming = true
    var retired = false
    var keepVisibleWhenRetiring = false
    var baseline: CGFloat
    let pack: LoadedPack
    let index: Int
    var frameTextures: [String: [SKTexture]] = [:]
    var frameAlphaMasks: [String: [[UInt8]]] = [:]
    /// Share of the frame height that is transparent above the art in every frame of this pack.
    var clearAboveArt: CGFloat = 0
    /// How far the session card rises above the cat window: it overlaps the empty space above the art.
    var cardReserve: CGFloat { max(0, ActivityBar.height + ActivityBar.gap - emptySpaceAboveArt) }
    /// Transparent space between the top of the window and the highest point the art reaches.
    var emptySpaceAboveArt: CGFloat {
        let artTop = node.position.y + node.size.height * (1 - node.anchorPoint.y) - clearAboveArt * node.size.height
        return max(0, panel.frame.height - artTop)
    }
    var currentFrameIndex = 0
    var step = 0
    var lastInteraction: TimeInterval = 0
    var monitoredSessionKey: String?
    var playback = AnimationPlayback()
    var animationDurations: [String: TimeInterval] = [:]
    var preferences = PetPreferences()
    var onSettings: (() -> Void)?
    var onClose: (() -> Void)?

    init(pack: LoadedPack, screen: NSScreen, index: Int, physicalBottom: Bool) throws {
        self.pack = pack; self.index = index
        let rendering = pack.manifest.rendering
        let scale = CGFloat(rendering.displayHeight) / CGFloat(rendering.frameSize[1])
        let width = CGFloat(rendering.frameSize[0]) * scale
        let height = CGFloat(rendering.displayHeight)
        baseline = (physicalBottom ? screen.frame.minY : screen.standingFrame.minY) - 12
        panel = NSPanel(contentRect: NSRect(x: screen.visibleFrame.minX + 150 + CGFloat(index)*150,
                                           y: baseline, width: width, height: height+24),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Pet Lab \(index+1)"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        view = PetView(frame: NSRect(origin: .zero, size: panel.frame.size))
        view.footInset = 12
        view.allowsTransparency = true; view.preferredFramesPerSecond = petFramesPerSecond
        view.setAccessibilityLabel("Pet Lab diagnostic companion \(index+1)")
        panel.contentView = view
        scene = SKScene(size: panel.frame.size); scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill
        node = SKSpriteNode(color: .clear, size: NSSize(width: width, height: height))
        node.anchorPoint = NSPoint(x: CGFloat(rendering.anchor[0]) / CGFloat(rendering.frameSize[0]),
                                  y: 1 - CGFloat(rendering.anchor[1]) / CGFloat(rendering.frameSize[1]))
        node.position = NSPoint(x: width/2, y: 12)
        scene.addChild(node)
        label = SKLabelNode(fontNamed: "Menlo-Bold"); label.fontSize = 10; label.fontColor = .white
        label.position = NSPoint(x: width/2, y: height + 6)
        scene.addChild(label); view.presentScene(scene)
        var sheets: [String: CGImage] = [:]
        for (name, animation) in pack.manifest.animations {
            animationDurations[name] = animation.frames.indices.reduce(0) { $0 + animation.duration(at: $1) }
            let url = pack.root.appendingPathComponent(animation.image)
            if sheets[animation.image] == nil {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw PackError(message: "Image decode failed") }
                sheets[animation.image] = image
            }
            let sheet = sheets[animation.image]!
            let columns = sheet.width/rendering.frameSize[0]
            var masks: [[UInt8]] = []
            frameTextures[name] = try animation.frames.map { frame in
                guard let image = sheet.cropping(to: CGRect(x: (frame % columns)*rendering.frameSize[0],
                                                           y: (frame / columns)*rendering.frameSize[1],
                                                           width: rendering.frameSize[0], height: rendering.frameSize[1])) else {
                    throw PackError(message: "Frame crop failed")
                }
                let texture = SKTexture(cgImage: image)
                texture.filteringMode = rendering.filtering == "nearest" ? .nearest : .linear
                guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width*4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let bytes = context.data else {
                    throw PackError(message: "Alpha mask allocation failed")
                }
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                let rgba = bytes.assumingMemoryBound(to: UInt8.self)
                masks.append((0..<(image.width*image.height)).map { rgba[$0*4+3] })
                return texture
            }
            frameAlphaMasks[name] = masks
        }
        // Mask rows run top to bottom; find the highest opaque row any frame uses.
        let frameWidth = rendering.frameSize[0], frameHeight = rendering.frameSize[1]
        var topRow = frameHeight
        for mask in frameAlphaMasks.values.joined() {
            if let first = mask.firstIndex(where: { $0 > 16 }) { topRow = min(topRow, first / frameWidth) }
        }
        clearAboveArt = topRow < frameHeight ? CGFloat(topRow) / CGFloat(frameHeight) : 0
        view.onDrag = { [weak self] in
            self?.roaming = false; self?.roamingMotion = nil; self?.idleRoaming = nil
            self?.lastInteraction = ProcessInfo.processInfo.systemUptime
        }
        view.onClick = { [weak self] in
            guard let self else { return }
            self.lastInteraction = ProcessInfo.processInfo.systemUptime
            json(["interaction": "click", "pet": self.index])
        }
        view.onMenu = { [weak self] in self?.showMenu() }
        panel.orderFrontRegardless()
    }

    @objc func toggleRoaming() { roaming.toggle(); roamingMotion = nil; idleRoaming = nil }
    @objc func openSettings() { onSettings?() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func closeCat() { onClose?() }
    func showMenu() {
        let menu = NSMenu()
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(.separator())
        let roam = menu.addItem(withTitle: roaming ? "Pause roaming" : "Resume roaming", action: #selector(toggleRoaming), keyEquivalent: "")
        roam.target = self
        if onClose != nil {
            let close = menu.addItem(withTitle: "Close this cat", action: #selector(closeCat), keyEquivalent: "")
            close.target = self
        }
        let quit = menu.addItem(withTitle: "Quit Pet Lab", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 20), in: view)
    }

    func applyPreferences(_ value: PetPreferences) {
        let needsResize = preferences.sizeScale != value.sizeScale || node.position.y == 12
        preferences = value
        view.topAccessoryHeight = value.showSessionLabels && activityBar != nil ? cardReserve : 0
        if !value.showSessionLabels { activityBar?.panel.orderOut(nil) }
        guard needsResize else { return }
        let rendering = pack.manifest.rendering
        let layout = PetSizeLayout(frameSize: rendering.frameSize, anchor: rendering.anchor,
                                   displayHeight: rendering.displayHeight, scale: value.sizeScale)
        // Keep the feet on the same line while the window changes size.
        let origin = NSPoint(x: panel.frame.midX-layout.windowSize.width/2,
                             y: panel.frame.minY + view.footInset - layout.spritePosition.y)
        view.footInset = layout.spritePosition.y
        panel.setFrame(NSRect(origin: origin, size: layout.windowSize), display: true)
        view.frame = NSRect(origin: .zero, size: layout.windowSize); scene.size = layout.windowSize
        node.size = layout.spriteSize; node.position = layout.spritePosition
        if view.topAccessoryHeight > 0 { view.topAccessoryHeight = cardReserve }
        label.position = NSPoint(x: layout.windowSize.width/2, y: layout.spriteSize.height+6)
        if let screen = panel.screen ?? NSScreen.main {
            let bounds = DesktopGeometry.petBounds(on: screen.standingFrame, accessoryHeight: view.topAccessoryHeight, footInset: view.footInset)
            panel.setFrame(DesktopGeometry.clamp(panel.frame, to: bounds), display: true)
        }
        baseline = panel.frame.minY; roamingMotion = nil; idleRoaming = nil
    }

    func animate(_ requested: String) {
        let name = frameTextures[requested] == nil ? "idle" : requested
        guard animationName != name, let textures = frameTextures[name], let definition = pack.manifest.animations[name] else { return }
        animationName = name; node.removeAction(forKey: "frames"); node.alpha = 1; step = 0
        let actions = textures.enumerated().map { i, texture in
            SKAction.sequence([.run { [weak self] in
                self?.node.texture = texture; self?.currentFrameIndex = i; self?.step += 1
            }, .wait(forDuration: definition.duration(at: i))])
        }
        let sequence = SKAction.sequence(actions)
        let once = ["retire", "spawn", "success", "error"].contains(name)
        if name == "retire" {
            retired = true
            node.run(.sequence([sequence, .run { [weak self] in
                guard let self, !self.keepVisibleWhenRetiring else { return }
                self.panel.orderOut(nil)
            }]), withKey: "frames")
        } else {
            retired = false
            node.run(once ? sequence : .repeatForever(sequence), withKey: "frames")
        }
    }

    func update(activity: Activity, title: String, screen: NSScreen, elapsed: TimeInterval) {
        if let bounds = DesktopGeometry.containingScreen(for: panel.frame, screens: NSScreen.screens.map(\.frame)) {
            let visible = NSScreen.screens.first(where: { $0.frame == bounds })?.standingFrame ?? bounds
            let allowed = DesktopGeometry.petBounds(on: visible, accessoryHeight: view.topAccessoryHeight, footInset: view.footInset)
            let clamped = DesktopGeometry.clamp(panel.frame, to: allowed)
            if panel.frame != clamped { panel.setFrame(clamped, display: false) }
        }
        if retired && activity != .retired { panel.orderFrontRegardless(); animationName = ""; retired = false }
        label.text = title
        let selectedAnimation = playback.advance(activity: activity, seconds: elapsed,
            interacted: ProcessInfo.processInfo.systemUptime-lastInteraction < 0.3,
            durations: animationDurations)
        var walkingNow = false
        if [.idle, .completed, .failed, .interrupted].contains(activity) && roaming && preferences.allowWandering && selectedAnimation == "idle" {
            var behavior = idleRoaming ?? IdleRoaming()
            behavior.advance(seconds: elapsed)
            idleRoaming = behavior
            walkingNow = behavior.phase == .walking
        } else { idleRoaming = nil }
        animate(walkingNow ? "walk" : selectedAnimation)
        if walkingNow {
            let bounds = (panel.screen ?? screen).standingFrame
            let floor = bounds.minY - view.footInset
            baseline = min(max(baseline, floor), max(floor, bounds.maxY-view.topAccessoryHeight-panel.frame.height))
            var motion = roamingMotion ?? RoamingMotion(x: panel.frame.minX, direction: idleRoaming?.direction ?? 1)
            let x = motion.advance(seconds: elapsed, minX: bounds.minX, maxX: bounds.maxX-panel.frame.width)
            roamingMotion = motion
            panel.setFrameOrigin(NSPoint(x: x, y: baseline))
            let walk = pack.manifest.animations["walk"]
            if walk?.allowMirror == true { node.xScale = (walk?.facing == "left" ? -motion.direction : motion.direction) }
        } else { node.xScale = 1; roamingMotion = nil }
        if preferences.showSessionLabels && panel.isVisible {
            if activityBar?.panel.isVisible == false { activityBar?.panel.orderFrontRegardless() }
        } else { activityBar?.panel.orderOut(nil) }
        // Whole-window pass-through over actual transparent pixels. Freeze while handling input.
        if ProcessInfo.processInfo.systemUptime-lastInteraction > 0.3 {
            let local = NSPoint(x: NSEvent.mouseLocation.x-panel.frame.minX,
                                y: NSEvent.mouseLocation.y-panel.frame.minY)
            let rect = node.calculateAccumulatedFrame()
            // CPU alpha masks avoid reading texture pixels back from the GPU every tick.
            var opaque = false
            if rect.contains(local), let masks = frameAlphaMasks[animationName], masks.indices.contains(currentFrameIndex) {
                let w = pack.manifest.rendering.frameSize[0], h = pack.manifest.rendering.frameSize[1]
                var px = min(w-1, max(0, Int((local.x-rect.minX)/rect.width*CGFloat(w))))
                if node.xScale < 0 { px = w-1-px }
                let py = min(h-1, max(0, Int((1-(local.y-rect.minY)/rect.height)*CGFloat(h))))
                opaque = masks[currentFrameIndex][py*w+px] > 32
            }
            panel.ignoresMouseEvents = !opaque
        }
    }

    func capture(to url: URL) throws {
        guard let texture = view.texture(from: scene) else { throw PackError(message: "Scene capture failed") }
        let rep = NSBitmapImageRep(cgImage: texture.cgImage())
        guard let png = rep.representation(using: .png, properties: [:]) else { throw PackError(message: "PNG encoding failed") }
        try png.write(to: url)
    }
}

final class LabDelegate: NSObject, NSApplicationDelegate {
    var pets: [PetWindow] = []
    let store = SessionStore()
    var timer: Timer?
    var started = ProcessInfo.processInfo.systemUptime
    var lastTick = ProcessInfo.processInfo.systemUptime
    var lastReport: TimeInterval = -2
    var loadedFiles: Set<String> = []
    var captured = false
    let duration = Double(option("--duration", fallback: arguments.contains("--state-file") ? "0" : "60")) ?? 60
    let count = max(1, min(8, Int(option("--pets", fallback: "1")) ?? 1))
    let queue = arguments.contains("--events") ? URL(fileURLWithPath: option("--events", fallback: "")) : nil
    let output = URL(fileURLWithPath: option("--output", fallback: FileManager.default.temporaryDirectory.appendingPathComponent("PetLab/overlay").path))
    let perSession = arguments.contains("--per-session")
    var multicats = arguments.contains("--multicats")
    var monitorPets: [String: PetWindow] = [:]
    var retiringUntil: [String: TimeInterval] = [:]
    /// Sessions whose cat the user closed; cleared when the session ends or on "Bring back closed cats".
    var closedSessionKeys: Set<String> = []
    var cachedPacks: [String: LoadedPack] = [:]
    var sessionKeys: [String] = []
    var pack: LoadedPack!
    let stateFile = arguments.contains("--state-file") ? URL(fileURLWithPath: option("--state-file", fallback: "")) : nil
    var monitorSnapshot: MonitorSnapshot?
    var monitorHealthy = false
    var lastSnapshotRead: TimeInterval = -1
    var snapshotModified: Date?
    var preferencesModified: Date?
    var preferencesChecked = false
    var retirementUntil: TimeInterval = 0
    var preferences = PetPreferences.load(from: preferencesURL)
    var settingsController: SettingsWindowController?
    var settingsSignal: DispatchSourceSignal?
    var statusItem: NSStatusItem?
    var statusMenu: NSMenu?
    var lastPreferencesRead: TimeInterval = -1
    var capturedSettings: Set<String> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            pack = try LoadedPack(directory: packURL)
            guard let screen = NSScreen.main else { throw PackError(message: "No screen") }
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            if stateFile != nil && multicats {
                // The snapshot creates one independently animated cat per live session.
            } else if stateFile != nil {
                pets.append(try PetWindow(pack: pack, screen: screen, index: 0, physicalBottom: arguments.contains("--physical-bottom")))
                pets[0].keepVisibleWhenRetiring = true
                pets[0].label.isHidden = true
                pets[0].view.topAccessoryHeight = pets[0].cardReserve
                pets[0].activityBar = ActivityBar(parent: pets[0].panel)
            } else if queue == nil {
                for i in 0..<count { pets.append(try PetWindow(pack: pack, screen: screen, index: i, physicalBottom: arguments.contains("--physical-bottom"))) }
            } else if !perSession {
                pets.append(try PetWindow(pack: pack, screen: screen, index: 0, physicalBottom: arguments.contains("--physical-bottom")))
            }
            for pet in pets { configurePet(pet) }
            signal(SIGUSR1, SIG_IGN)
            settingsSignal = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
            settingsSignal?.setEventHandler { [weak self] in self?.showSettings() }
            settingsSignal?.resume()
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = statusItem?.button {
                let image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Pet Lab Settings")
                image?.isTemplate = true; image?.size = NSSize(width: 18, height: 18)
                button.image = image
                button.toolTip = "Pet Lab Settings · Right-click for more options"
                button.setAccessibilityLabel("Pet Lab Settings")
                button.target = self; button.action = #selector(statusItemClicked(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            let menu = NSMenu()
            let settings = menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
            settings.target = self
            menu.addItem(.separator())
            let quit = menu.addItem(withTitle: "Quit Pet Lab", action: #selector(quitFromMenu), keyEquivalent: "q")
            quit.target = self; statusMenu = menu
            json(["started": true, "mode": stateFile != nil ? (multicats ? "multicats" : "shared") : queue == nil ? "synthetic-demo" : "event-queue", "displayCount": NSScreen.screens.count,
                  "decodedPixelBytes": pack.decodedBytes, "appActive": NSApp.isActive])
            timer = Timer.scheduledTimer(withTimeInterval: 1.0/Double(petFramesPerSecond), repeats: true) { [weak self] _ in self?.tick() }
        } catch { fputs("Pet Lab: \(error.localizedDescription)\n", stderr); exit(1) }
    }

    func configurePet(_ pet: PetWindow) {
        pet.applyPreferences(preferences)
        pet.onSettings = { [weak self] in self?.showSettings() }
    }

    @objc func quitFromMenu() { NSApp.terminate(nil) }
    static let restoreTag = 7301
    @objc func restoreClosedCats() { closedSessionKeys.removeAll() }
    func closeCat(for key: String) { closedSessionKeys.insert(key) }

    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            guard let menu = statusMenu else { return }
            menu.items.filter { $0.tag == Self.restoreTag }.forEach(menu.removeItem)
            if !closedSessionKeys.isEmpty {
                let count = closedSessionKeys.count
                let restore = NSMenuItem(title: "Bring back closed cats (\(count))", action: #selector(restoreClosedCats), keyEquivalent: "")
                restore.target = self; restore.tag = Self.restoreTag
                menu.insertItem(restore, at: 1)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
        } else { showSettings() }
    }

    @objc func showSettings() {
        if settingsController == nil {
            let selected = pets.first?.pack ?? pack!
            guard let definition = selected.manifest.animations["idle"],
                  let source = CGImageSourceCreateWithURL(selected.root.appendingPathComponent(definition.image) as CFURL, nil),
                  let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
            let size = selected.manifest.rendering.frameSize, columns = sheet.width/selected.manifest.rendering.frameSize[0]
            let textures = definition.frames.compactMap { frame -> SKTexture? in
                guard let image = sheet.cropping(to: CGRect(x: (frame%columns)*size[0], y: (frame/columns)*size[1], width: size[0], height: size[1])) else { return nil }
                let texture = SKTexture(cgImage: image); texture.filteringMode = .nearest; return texture
            }
            settingsController = SettingsWindowController(preferences: preferences, multicats: multicats, textures: textures,
                durations: definition.frames.indices.map { definition.duration(at: $0) }) { [weak self] value in
                    try value.save(to: preferencesURL)
                    self?.preferences = value
                    for pet in self?.pets ?? [] { pet.applyPreferences(value) }
                }
        }
        settingsController?.refresh(preferences, multicats: multicats); settingsController?.present()
    }

    func applyMode(snapshot: MonitorSnapshot, screen: NSScreen) throws {
        guard let mode = snapshot.mode, ["shared", "multicats"].contains(mode) else { return }
        let wanted = mode == "multicats"
        guard wanted != multicats else { return }
        let shared: LoadedPack
        if !wanted, let directory = snapshot.sharedPack { shared = try LoadedPack(directory: URL(fileURLWithPath: directory)) }
        else { shared = pack }
        for pet in pets {
            pet.node.removeAllActions(); pet.activityBar?.panel.close(); pet.panel.close()
        }
        pets.removeAll(); monitorPets.removeAll(); retiringUntil.removeAll(); retirementUntil = 0
        multicats = wanted
        if !wanted {
            pack = shared
            let pet = try PetWindow(pack: shared, screen: screen, index: 0, physicalBottom: arguments.contains("--physical-bottom"))
            pet.keepVisibleWhenRetiring = true; pet.label.isHidden = true
            pet.activityBar = ActivityBar(parent: pet.panel); configurePet(pet); pets = [pet]
        }
        settingsController?.refresh(preferences, multicats: multicats)
    }

    func reconcileCats(snapshot: MonitorSnapshot, screen: NSScreen, elapsed: TimeInterval) throws {
        closedSessionKeys.formIntersection(snapshot.sessions.map(\.key))
        let shown = snapshot.sessions.filter { !closedSessionKeys.contains($0.key) }
        let active = Set(shown.map(\.key))
        for session in shown {
            retiringUntil.removeValue(forKey: session.key)
            guard monitorPets[session.key] == nil else { continue }
            let directory = session.pack ?? pack.root.path
            let cat: LoadedPack
            if let cached = cachedPacks[directory] { cat = cached }
            else {
                cat = try LoadedPack(directory: URL(fileURLWithPath: directory))
                cachedPacks[directory] = cat
            }
            let used = Set(monitorPets.values.map(\.index))
            var slot = 0
            while used.contains(slot) { slot += 1 }
            let pet = try PetWindow(pack: cat, screen: screen, index: slot, physicalBottom: arguments.contains("--physical-bottom"))
            pet.monitoredSessionKey = session.key
            pet.label.isHidden = true
            pet.view.topAccessoryHeight = pet.cardReserve
            pet.activityBar = ActivityBar(parent: pet.panel)
            let key = session.key
            let close: () -> Void = { [weak self] in self?.closeCat(for: key) }
            pet.onClose = close; pet.activityBar?.onClose = close
            configurePet(pet)
            let columns = max(1, Int(screen.visibleFrame.width / 300))
            let origin = NSPoint(x: screen.visibleFrame.minX + 30 + CGFloat(slot % columns)*300,
                                 y: screen.standingFrame.minY - pet.view.footInset + CGFloat(slot / columns)*(pet.panel.frame.height + ActivityBar.height + 26))
            pet.panel.setFrameOrigin(origin); pet.baseline = origin.y
            monitorPets[session.key] = pet
        }
        for key in Array(monitorPets.keys) where !active.contains(key) {
            guard let pet = monitorPets[key] else { continue }
            if retiringUntil[key] == nil {
                retiringUntil[key] = elapsed + (pet.animationDurations["retire"] ?? 1) + 0.3
            }
            if elapsed >= retiringUntil[key]! {
                pet.node.removeAllActions()
                pet.activityBar?.panel.close(); pet.panel.close()
                monitorPets.removeValue(forKey: key); retiringUntil.removeValue(forKey: key)
            }
        }
        pets = monitorPets.values.sorted { $0.index < $1.index }
    }

    func tick() {
        if arguments.contains("--parent-pid"), let parent = Int32(option("--parent-pid", fallback: "0")), parent > 0, getppid() != parent {
            NSApp.terminate(nil); return
        }
        let now = ProcessInfo.processInfo.systemUptime, elapsed = now-started
        defer { lastTick = now }
        guard let screen = NSScreen.screens.first else { return }
        if elapsed-lastPreferencesRead >= 0.5 {
            lastPreferencesRead = elapsed
            // Only decode preferences when the file changed (or appeared/disappeared).
            let modified = (try? preferencesURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let changed = !preferencesChecked || modified != preferencesModified
            preferencesChecked = true; preferencesModified = modified
            let saved = changed ? PetPreferences.load(from: preferencesURL) : preferences
            if saved != preferences {
                preferences = saved
                for pet in pets { pet.applyPreferences(saved) }
                settingsController?.refresh(saved, multicats: multicats)
            }
        }
        if let stateFile, elapsed-lastSnapshotRead >= 0.25 {
            lastSnapshotRead = elapsed
            let values = try? stateFile.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            if let modified = values?.contentModificationDate, modified == snapshotModified, let snapshot = monitorSnapshot {
                // Unchanged since the last parse: only staleness and cat retirement timers advance.
                monitorHealthy = Date().timeIntervalSince(modified) < 10
                if monitorHealthy && multicats {
                    do { try reconcileCats(snapshot: snapshot, screen: screen, elapsed: elapsed) }
                    catch { fputs("Pet Lab: \(error.localizedDescription)\n", stderr); NSApp.terminate(nil); return }
                }
            } else if let values,
               (values.fileSize ?? Int.max) <= 1048576,
               let modified = values.contentModificationDate, Date().timeIntervalSince(modified) < 10,
               let data = try? Data(contentsOf: stateFile),
               let snapshot = try? JSONDecoder().decode(MonitorSnapshot.self, from: data), snapshot.schemaVersion == 1 {
                do { try applyMode(snapshot: snapshot, screen: screen) }
                catch { fputs("Pet Lab: \(error.localizedDescription)\n", stderr); NSApp.terminate(nil); return }
                let busy = [Activity.working, .attention].contains(snapshot.sharedActivity)
                if !multicats, let old = monitorSnapshot,
                   !Set(old.sessions.map(\.key)).subtracting(snapshot.sessions.map(\.key)).isEmpty,
                   !busy, let animation = pack.manifest.animations["retire"] {
                    retirementUntil = elapsed + animation.frames.indices.reduce(0.0) { $0 + animation.duration(at: $1) }
                }
                if busy { retirementUntil = 0 }
                monitorSnapshot = snapshot; monitorHealthy = true; snapshotModified = modified
                if multicats {
                    do { try reconcileCats(snapshot: snapshot, screen: screen, elapsed: elapsed) }
                    catch { fputs("Pet Lab: \(error.localizedDescription)\n", stderr); NSApp.terminate(nil); return }
                }
            } else { monitorHealthy = false }
        }
        if let queue {
            let urls = ((try? FileManager.default.contentsOfDirectory(at: queue, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "json" && !loadedFiles.contains($0.lastPathComponent) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            for url in urls {
                if let data = try? Data(contentsOf: url), let event = try? JSONDecoder().decode(SessionEvent.self, from: data) {
                    store.apply(event); loadedFiles.insert(url.lastPathComponent)
                    if perSession && !sessionKeys.contains(event.key) && pets.count < 8 {
                        if let pet = try? PetWindow(pack: pack, screen: screen, index: pets.count, physicalBottom: arguments.contains("--physical-bottom")) {
                            configurePet(pet)
                            sessionKeys.append(event.key); pets.append(pet)
                        }
                    }
                }
            }
        }
        for (index, pet) in pets.enumerated() {
            let activity: Activity
            let ownKey = pet.monitoredSessionKey
            if stateFile != nil && multicats, let ownKey {
                activity = !monitorHealthy ? .uncertain : retiringUntil[ownKey] != nil ? .retired
                    : monitorSnapshot?.sessions.first(where: { $0.key == ownKey })?.activity ?? .uncertain
            } else if stateFile != nil {
                activity = !monitorHealthy ? .uncertain : elapsed < retirementUntil ? .retired : monitorSnapshot?.sharedActivity ?? .idle
            } else if queue != nil {
                activity = perSession ? (store.sessions[sessionKeys[index]]?.activity ?? .uncertain) : store.sharedActivity
            } else {
                // Explicitly synthetic stages: roam, sustained work, attention, retirement.
                let offset = elapsed-Double(index)*1.2
                activity = arguments.contains("--hold-working") && offset >= 3 ? .working
                    : offset < 3 ? .idle : offset < 15 ? .working : offset < 18 ? .attention : offset < 21 ? .idle : .retired
            }
            pet.update(activity: activity, title: "\(index+1) \(activity.rawValue)", screen: screen, elapsed: now-lastTick)
            pet.activityBar?.update(snapshot: ownKey.flatMap { monitorSnapshot?.forSession($0) } ?? monitorSnapshot,
                                    healthy: monitorHealthy, parent: pet.panel, emptySpaceAbove: pet.emptySpaceAboveArt)
        }
        if elapsed-lastReport >= 1 {
            let samples: [[String: Any]] = pets.prefix(64).map { pet in
                let barCount: Int
                if let key = pet.monitoredSessionKey { barCount = monitorSnapshot?.forSession(key).sessions.count ?? 0 }
                else { barCount = monitorSnapshot?.sessions.count ?? 0 }
                return ["pack": pet.pack.root.lastPathComponent, "animation": pet.animationName, "frame": pet.currentFrameIndex,
                        "frameChanges": pet.step, "visible": pet.panel.isVisible, "clickThrough": pet.panel.ignoresMouseEvents,
                        "activityBarVisible": pet.activityBar?.panel.isVisible ?? false, "barSessionCount": barCount,
                        "roaming": pet.roaming && preferences.allowWandering, "windowX": pet.panel.frame.minX, "windowY": pet.panel.frame.minY,
                        "displayHeight": pet.node.size.height, "emptyAboveArt": pet.emptySpaceAboveArt,
                        "roamingPhase": pet.idleRoaming?.phase.rawValue ?? "inactive"]
            }
            json(["elapsed": Int(elapsed), "appActive": NSApp.isActive, "events": loadedFiles.count,
                  "working": stateFile != nil ? monitorSnapshot?.sessions.filter { $0.activity == .working }.count ?? 0 : store.sessions.values.filter { $0.activity == .working }.count,
                  "petCount": pets.count,
                  "mode": multicats ? "multicats" : "shared",
                  "menuBarIconVisible": statusItem?.isVisible ?? false,
                  "preferences": ["sizeScale": preferences.sizeScale, "allowWandering": preferences.allowWandering, "showSessionLabels": preferences.showSessionLabels, "multicats": multicats],
                  "settingsVisible": settingsController?.window?.isVisible ?? false,
                  "pets": samples])
            if arguments.contains("--capture-settings"), settingsController?.window?.isVisible == true {
                let key = "\(Int(preferences.sizeScale*100))-\(preferences.allowWandering)-\(preferences.showSessionLabels)"
                if !capturedSettings.contains(key) {
                    try? settingsController?.capture(to: output.appendingPathComponent("settings-\(key).png"))
                    capturedSettings.insert(key)
                }
            }
            lastReport = elapsed
        }
        if !captured && elapsed > 6 {
            for (i, pet) in pets.enumerated() { try? pet.capture(to: output.appendingPathComponent("pet-\(i+1)-working.png")) }
            if arguments.contains("--capture-activity-bar") {
                try? pets.first?.activityBar?.capture(to: output.appendingPathComponent("activity-bar.png"))
            }
            captured = true
        }
        if duration > 0 && elapsed >= duration { NSApp.terminate(nil) }
    }
}

if arguments.contains("--lock-run") {
    guard let separator = arguments.firstIndex(of: "--"), separator+1 < arguments.count else { exit(64) }
    let filename = option("--lock-run", fallback: "")
    let descriptor = Darwin.open(filename, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { perror("Pet Lab lock"); exit(1) }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
        if errno == EWOULDBLOCK { exit(0) }
        perror("Pet Lab lock"); exit(1)
    }
    setenv("PET_LAB_LOCK_FD", String(descriptor), 1)
    let command = Array(arguments[(separator+1)...])
    let pointers = command.map { strdup($0) } + [nil]
    pointers.withUnsafeBufferPointer { buffer in _ = execv(command[0], buffer.baseAddress!) }
    perror("Pet Lab monitor"); exit(1)
} else if arguments.contains("--validate") {
    do {
        let pack = try LoadedPack(directory: packURL)
        json(["valid": true, "name": pack.manifest.name, "animations": pack.manifest.animations.count,
              "referencedFrames": pack.manifest.animations.values.reduce(0) { $0+$1.frames.count }, "decodedPixelBytes": pack.decodedBytes])
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else if arguments.contains("--replay") {
    let directory = URL(fileURLWithPath: option("--replay", fallback: ""))
    let store = SessionStore()
    let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    for url in urls {
        let event = try JSONDecoder().decode(SessionEvent.self, from: Data(contentsOf: url)); store.apply(event)
        json(["event": event.kind, "provider": event.provider, "shared": store.sharedActivity.rawValue,
              "session": store.sessions[event.key]!.activity.rawValue])
    }
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = LabDelegate(); app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
