# Pet pack contract draft

The version 1 prototype uses an unpacked directory containing `manifest.json` and 8-bit PNG sprite sheets. It establishes a testable format for community authors. It is not yet a published compatibility promise.

```text
my-pet/
  manifest.json
  sprites/
    idle.png
    walk.png
    working.png
    retire.png
  LICENSE.txt
```

The starter manifest provides a complete example. `id` identifies a pack, `artworkVersion` identifies its art revision, and `formatVersion` identifies the interpretation of its manifest. Authors provide their name and an artwork license. The application must not assume imported art is redistributable.

Frames share one size across a pack. A sheet's dimensions must be exact multiples of that size. Frame indices begin at zero, left-to-right then top-to-bottom. Indices may repeat to reuse images, and each referenced frame counts toward the animation and pack budgets. The ground anchor uses top-left pixel coordinates and is shared across frames. Display height uses macOS logical points. `nearest` filtering preserves pixel-art edges; `linear` interpolates.

An animation supplies `image`, `frames`, and a default `frameDurationMs`. Optional `frameDurationsMs` supplies one duration per frame, taking precedence over the default. Optional `frameOffsets` supplies one `[x, y]` translation per frame reference, in source pixels (right/down positive). The renderer adjusts the anchor without changing the artwork or timing; omitted offsets are zero. Each adjusted anchor must remain inside the frame. This compensates for registration drift while preserving distinct poses. Older readers that reject unknown properties cannot load packs using this extension. Optional walk `facing` and `allowMirror` control horizontal mirroring. The app owns playback lifetime; packs do not contain executable code or completion timers.

| Animation | Requirement | Playback contract |
| --- | --- | --- |
| idle | Required | Loop while idle |
| walk | Required | Loop while roaming |
| working | Required | Loop while the session remains working |
| retire | Required | Once, then hide that session pet |
| spawn | Optional | Once on idle startup; falls back to idle |
| attention | Optional | Loop while waiting; prototype falls back to idle |
| success / error | Optional | Once on explicit completion/failure, then rest |
| sleep | Optional | Loop after two minutes idle; activity or interaction wakes |

The renderer supports all nine states. Missing optional animations fall back to idle. Success and error require explicit result events; the current live Claude registry reports busy/idle and does not provide those results. Shared persistent mode keeps the companion visible after a session retires. Attention is also represented in the activity bar.

Provisional limits:

- 1–64 references per animation; at most 256 across a pack.
- Frames: at most 1024 × 1024 pixels; sheets: at most 4096 × 4096 pixels.
- At most 64 MiB of estimated RGBA8 sheet pixels, counting shared files once.
- Durations: 16–2000 ms per frame. This range supports still poses through slow loops but is not a performance guarantee.
- Display height: 16–256 points. Manifest size: at most 64 KiB.
- Image and manifest symlinks must remain inside the selected directory; traversal paths are rejected.

The JSON Schema describes field shapes. Native validation additionally checks image contents, dimensions, anchors, path containment, total frames and pixel budget. Resource measurements with the small starter pack do not validate maximum-size packs. GPU allocation, scaling and additional decoded buffers can exceed the sheet pixel estimate.

Before accepting `.petpack` archives, an importer must enforce compressed/uncompressed limits, reject traversal and symlinks during extraction, validate in a temporary directory, and install atomically. The current directory validator is not an archive-extraction defense.
