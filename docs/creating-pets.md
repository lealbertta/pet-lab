# Creating a pet

## 1. Copy a working pack

```sh
cp -R packs/starter packs/my-pet
```

Edit `manifest.json`: give the pet a unique `id`, `name`, `author`, artwork `license`, and `artworkVersion`. Keep `formatVersion` at `1`. Replace `LICENSE.txt` with accurate artwork attribution and usage terms. Only include art you have permission to use.

## 2. Draw the sprites

Use transparent, 8-bit PNG sprite sheets. Every frame in a pack must use the same canvas dimensions. Sheets must be exact multiples of those dimensions. Frame indices start at zero, running left to right and then top to bottom.

Keep the character's proportions, markings, and ground line consistent across frames. Leave room for ears, tails, movement, and props within every cell. Avoid grid lines and shadows baked into the transparent background. Use `nearest` filtering for crisp pixel art.

The starter uses 64 × 64 frames. Larger frames also work; matching the existing cats' 209 × 209 canvases is not required. The `anchor` specifies a common ground point using top-left pixel coordinates. `displayHeight` is the pet's base height in macOS points; the user's Settings scale multiplies it.

## 3. Define the animations

Required: `idle`, `walk`, `working`, and `retire`.

Recommended: `spawn`, `attention`, `success`, `error`, and `sleep`.

Each animation points to an image, frame indices, and a default `frameDurationMs`. Optional `frameDurationsMs` allows varied timing. Walk animations can declare `facing` and `allowMirror`.

Give your pet a personality: calm blinking, a characteristic walk, keyboard mashing, laptop pouncing, or a sleepy stretch. The app controls when an animation plays. Missing optional artwork falls back to idle; no code belongs in a pet pack.

See the [complete format and limits](pet-packs.md) and the [Calico example](../packs/cat-01-calico/manifest.json).

## 4. Validate and preview

After building the app:

```sh
"native/Pet Lab.app/Contents/MacOS/pet-lab" --validate --pack packs/my-pet
swift -module-cache-path .build/preview-cache tools/preview_pack.swift packs/my-pet artifacts/my-pet-preview
```

Inspect the generated animation GIFs for clipping, shifting, inconsistent markings, and awkward loop transitions. Validation checks file paths, dimensions, frame indices, durations, metadata, and memory limits; it cannot judge visual quality.

To try the pet:

```sh
node bin/pet-lab.mjs stop
PET_LAB_PACK="$PWD/packs/my-pet" node bin/pet-lab.mjs settings
```

Turn multicats mode off in Settings to use the custom shared pet. A running instance preserves its existing pack, which is why the stop command comes first.

## 5. Add a cat to the random library

For automatic inclusion in the cat picker and multicats library, use a unique directory named `packs/cat-XX-name`, such as `packs/cat-16-my-cat`, with two digits and a lowercase name containing letters or hyphens. Include a valid manifest and all referenced PNGs. Run `node bin/pet-lab.mjs cats` to check discovery.

The app currently loads unpacked directories. A `.petpack` archive importer is not implemented.
