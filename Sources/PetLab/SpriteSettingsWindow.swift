import AppKit
import SwiftUI
import PetCore

private struct SpriteChoice: Identifiable {
    let id: String
    let name: String
    let thumbnail: NSImage?
}

private final class SpriteChoices: ObservableObject {
    @Published var sprites: [SpriteChoice] = []
    @Published var disabled: Set<String> = []
    @Published var error: String?
    var change: (Bool, [String]) -> Void = { _, _ in }
}

private struct SpritePicker: View {
    @ObservedObject var model: SpriteChoices
    private var enabledCount: Int { model.sprites.filter { !model.disabled.contains($0.id) }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose your sprites").font(.system(size: 23, weight: .bold))
                Text("Turn on the companions you’d like to see in Multicats.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("\(enabledCount) of \(model.sprites.count) enabled")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button("Enable all") { model.change(true, model.sprites.map(\.id)) }
                    .disabled(enabledCount == model.sprites.count)
                Button("Disable all") { model.change(false, model.sprites.map(\.id)) }
                    .disabled(enabledCount == 0)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                    ForEach(model.sprites) { sprite in
                        card(sprite)
                    }
                }
                .padding(3)
            }
            if let error = model.error {
                Text(error).foregroundStyle(.red).font(.system(size: 12))
            } else {
                Text(model.sprites.isEmpty ? "No sprites available." : enabledCount == 0
                     ? "All sprites are off. Multicats pets are hidden."
                     : "Changes apply immediately · Saved automatically")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func card(_ sprite: SpriteChoice) -> some View {
        let enabled = !model.disabled.contains(sprite.id)
        return VStack(spacing: 6) {
            Button { model.change(!enabled, [sprite.id]) } label: {
                Group {
                    if let image = sprite.thumbnail {
                        Image(nsImage: image).resizable().interpolation(.none).scaledToFit()
                    } else {
                        Image(systemName: "photo").resizable().scaledToFit().foregroundStyle(.secondary)
                    }
                }
                .frame(width: 40, height: 40)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(enabled ? "Disable" : "Enable") \(sprite.name)")
            Toggle(isOn: Binding(get: { !model.disabled.contains(sprite.id) },
                                 set: { model.change($0, [sprite.id]) })) {
                Text(enabled ? "On" : "Off").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(enabled ? .primary : .secondary)
            }
            .toggleStyle(.switch).controlSize(.mini)
            .accessibilityLabel(sprite.name)
            .fixedSize()
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(enabled
            ? Color.accentColor.opacity(0.09) : Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(enabled
            ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.1), lineWidth: 1))
        .help(sprite.name)
    }
}

final class SpriteSettingsWindowController: NSWindowController {
    private var preferences: PetPreferences
    private let onChange: ([String]) throws -> Void
    private let model = SpriteChoices()
    private var loadError: String?

    init(packsURL: URL, preferences: PetPreferences, onChange: @escaping ([String]) throws -> Void) {
        self.preferences = preferences; self.onChange = onChange
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 570),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Sprites"; window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 470)
        super.init(window: window)
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: packsURL, includingPropertiesForKeys: nil)
            for url in urls.filter({ $0.lastPathComponent.range(of: "^(cat|shiba|dog)-[0-9]{2}-[a-z-]+$", options: .regularExpression) != nil })
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                do {
                    let manifest = try JSONDecoder().decode(PackManifest.self, from: Data(contentsOf: url.appendingPathComponent("manifest.json")))
                    model.sprites.append(SpriteChoice(id: url.lastPathComponent, name: manifest.name,
                                                      thumbnail: Self.thumbnail(for: manifest, at: url)))
                } catch {
                    loadError = "Some sprites couldn’t be loaded. Restart Pet Lab to retry."
                }
            }
        } catch {
            loadError = "Couldn’t load the sprite library. Restart Pet Lab to retry."
        }
        model.change = { [weak self] enabled, ids in self?.setEnabled(enabled, ids: ids) }
        window.contentView = NSHostingView(rootView: SpritePicker(model: model))
        refresh(preferences); window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private static func thumbnail(for manifest: PackManifest, at url: URL) -> NSImage? {
        let size = manifest.rendering.frameSize
        guard size.count == 2, size[0] > 0, size[1] > 0,
              let idle = manifest.animations["idle"], let frame = idle.frames.first, frame >= 0,
              let image = NSImage(contentsOf: url.appendingPathComponent(idle.image)),
              let sheet = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let columns = sheet.width / size[0]
        guard columns > 0, frame / columns < sheet.height / size[1],
              let crop = sheet.cropping(to: CGRect(x: (frame % columns) * size[0],
                                                  y: (frame / columns) * size[1],
                                                  width: size[0], height: size[1])) else { return nil }
        return NSImage(cgImage: crop, size: NSSize(width: size[0], height: size[1]))
    }
    func refresh(_ value: PetPreferences) {
        preferences = value
        model.disabled = Set(value.disabledSprites)
        model.error = loadError
    }
    private func setEnabled(_ enabled: Bool, ids: [String]) {
        var disabled = Set(preferences.disabledSprites)
        if enabled { disabled.subtract(ids) } else { disabled.formUnion(ids) }
        do {
            try onChange(disabled.sorted())
            var value = preferences; value.disabledSprites = disabled.sorted(); refresh(value)
        } catch {
            refresh(preferences)
            model.error = "Couldn’t save changes. Please try again."
        }
    }
    func present() { showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
}
