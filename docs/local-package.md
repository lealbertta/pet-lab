# Local package

Pet Lab 0.6.0 is a private local npm package for Apple Silicon macOS. Build the native renderer with `npm run build:native` before packaging. The source repository does not contain compiled app bundles.

```sh
npm pack --offline --ignore-scripts
npm install --global --offline --ignore-scripts ./pet-lab-local-0.6.0.tgz
```

Start with `pet-lab`, open Settings with `pet-lab settings`, and stop with `pet-lab stop`. A normal click on the menu-bar paw opens Settings; right-click offers Settings and Quit. Calico is the default pet in this repository.

Settings include size (50–200%), multicats mode, idle wandering, and session-label visibility. Changes apply live and are stored in `preferences.json` inside `~/Library/Application Support/Pet Lab`. The selected mode and pet survive restarts. `pet-lab cat 03` chooses a single pet; `pet-lab -multicats` explicitly enables the random per-session library.

Multicats mode picks unused designs first, keeps assignments stable while the monitor runs, and balances repeats when more than twelve cats are needed. Each cat follows its own session. Departing cats play goodbye before their designs are released. With no sessions, multicats mode shows no pet windows; the menu-bar icon remains available.

Shared mode keeps one idle pet visible. Idle pets rest, take short walks, and nap after two minutes. Working pets remain stationary while their working animation loops. Clicks, dragging, or activity wake sleeping pets. Dragging pauses that individual pet's roaming until Resume roaming is selected from its menu.

Optional environment overrides:

| Variable | Purpose |
| --- | --- |
| `PET_LAB_PACK` | Absolute path to an unpacked shared pet pack |
| `PET_LAB_STATE_DIR` | Isolated runtime/preferences directory |
| `PET_LAB_CLAUDE_REGISTRY` | Alternate Claude registry directory for fixtures |

Stop a running instance before changing its pack or environment. Settings and mode changes do not require a restart.

The current registry adapter supports Claude CLI 2.1.311 only. It checks process creation identity, does not read prompts or transcripts, and does not change provider configuration. Explicit success/failure reactions require a separate result event source. Claude questions and approvals are not captured by this adapter.

The app uses a user-only Unix socket rather than a TCP listener. `pet-lab status --json` reports mode, preferences, counts, and up to 64 per-pet samples without session IDs or titles. The renderer still creates a cat for every discovered session.

The app bundle is an unsigned local development build. The package is private and cannot be published to npm without changing its metadata and choosing appropriate distribution terms.
