# Shiba companions

Four Shibas provide idle, walk, working, attention, success, error, sleep, spawn, and retire animations.

- 16: Red Shiba — front-facing laptop typing.
- 17: Black & Tan Shiba — four-paw keyboard stompies.
- 18: Sesame Shiba — cartoon leg-lift on a computer tower.
- 19: Cream Shiba — tablet tapping.

Run `node bin/pet-lab.mjs pets` to list companions and `node bin/pet-lab.mjs pet 16` through `19` to select one. Existing cat commands remain compatible.

Every pack uses a shared ground anchor; transparent padding prevents clipping and the success hop retains a deliberate 12-pixel lift. `ground-alignment.json` records offsets. Run `node tools/verify-shibas.mjs` after building the native app to check all 144 frame baselines, native loading, and working playback. `swift tools/preview-shiba-transitions.swift` exports a side-by-side GIF under the ignored artifacts directory.

Artwork was generated with built-in OpenAI ImageGen from the user-approved designs. The four PNG packs are self-contained; generation sources and previews remain in the local authoring workspace.
