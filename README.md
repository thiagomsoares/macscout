# Macscout

**English** · **[Português (Brasil)](README.pt-BR.md)**

<p align="center">
  <img src="docs/images/band.png" alt="Macscout collapsed band in the menu bar — caution icon, reading, delta and 12 h pixel trail" width="900">
</p>

<p align="center">
  <img src="docs/images/panel.png" alt="Macscout expanded panel — 24 h dot-matrix glucose chart" width="720">
</p>

<p align="center">
  <b>Your Nightscout, in the notch.</b><br>
  Live glucose from your <a href="https://nightscout.github.io/">Nightscout</a> site at the top of your screen —
  one glance, zero context switches.
</p>

<p align="center">
  macOS 14+ · Swift 6 · zero dependencies · English / Português (BR) · MIT · <b>#WeAreNotWaiting</b>
</p>

## Install

**[⬇ Download the latest DMG](https://github.com/thiagomsoares/macscout/releases/latest)** (v0.1.0)

1. Open the DMG and drag **Macscout** into **Applications**.
2. **First launch:** releases are not yet notarized by Apple (Developer ID signing is on the
   roadmap), so macOS will block the first open. Go to
   **System Settings → Privacy & Security**, scroll down and click **"Open Anyway"**, then confirm.
   You only do this once.
3. Macscout is an agent app: no Dock icon. It lives in the notch (or a floating pill on
   notch-less Macs) and the menu bar. Rest your pointer on the notch to expand the dashboard.

## Features

- **Live glucose in the notch** — a black pill that blends into the MacBook notch showing BG value, trend arrow, and delta in crisp pixel type (Departure Mono), color-coded the Nightscout way (green in range, yellow high, red low, gray stale). On Macs without a notch it floats just under the menu bar.
- **Notch-native interaction** — rest the pointer on the pill and it springs open (0.12 s hover delay, 0.35 s leave grace); click to pin it open. Expand/collapse uses a real spring animator (expand 0.40/0.70, collapse 0.34/0.85 — hand-tuned). Shape-aware hit testing keeps empty corners and the camera housing click-through to the menu bar; the first click counts without a focus steal; right-click the band for Open Panel / Refresh / Settings… / Quit. Stays visible above fullscreen apps.
- **Full dashboard** — green-phosphor dot-matrix glucose chart (pure Canvas) with target-range band, out-of-range dots in yellow/red, dose-weighted insulin lane, carb markers and hover tooltips; time-in-range stats, mean, and GMI over 6 / 12 / 24 h.
- **Menu bar readout** — `118 ↗` in the native system label color, with a tooltip showing data age and quick actions (Open Panel, Refresh, Settings…, Check for Updates…, Quit).
- **Check for Updates** — pulls the latest GitHub Release, and can download the DMG straight into `~/Downloads` and open it. Also in Settings → About. Quiet launch check surfaces only when something newer exists.
- **Configurable alerts** — urgent low / low / high / urgent high thresholds, rising/falling-fast delta alerts, stale-data alerts, per-category sounds, cooldowns, quiet hours (sounds muted only), and optional auto-expand of the panel on urgent alerts.
- **Synthesized 8-bit sound design** — every alert cue and the onboarding ceremony jingle are chiptunes generated in code (square/triangle waves, zero audio assets). Classic system sounds remain selectable per category.
- **A proper onboarding** — five short acts over a synthesized rays backdrop: live demo data in the notch while you read, a connection test that renders your real latest reading inside the card, recommended alert defaults, and a closing ceremony (confetti + jingle + pill landing bounce).
- **Demo mode** — synthetic CGM data so you can try the app without a Nightscout site.
- **Native and dependency-free** — pure SwiftUI / AppKit / Swift Charts. No third-party packages.

The design system (color tokens, typography, motion and sound specs) lives in [docs/DESIGN.md](docs/DESIGN.md).

## Requirements

- macOS 14 or later
- To build from source: Swift 6.2+ toolchain (Xcode Command Line Tools are enough — full Xcode is **not** required)

## Build

```sh
swift build -c release --product Macscout    # build the binary
scripts/build.sh                              # build + bundle dist/Macscout.app (ad-hoc signed)
swift test                                    # run the test suite
```

`scripts/build.sh` tries a universal (arm64 + x86_64) release build first and falls back to a plain build for your architecture, then assembles `dist/Macscout.app` and ad-hoc signs it (`codesign --sign -`).

The app icon is generated programmatically:

```sh
swift scripts/make-icon.swift   # regenerates Sources/Macscout/Resources/AppIcon.icns
```

## Run

```sh
open "dist/Macscout.app"
```

Macscout is an agent app (`LSUIElement`): no Dock icon. It lives in the notch area and the menu bar. On first launch it starts in **Demo mode** until you enter your Nightscout URL in Settings.

## Configuration

Open **Settings…** from the menu bar item or the panel.

### General

- **Nightscout URL** — e.g. `https://yoursite.example.com` (http/https only).
- **Token** — a Nightscout access token (Admin → Subjects). Sent as the `token` query parameter. Takes precedence over API secret when both are set.
- **API secret** — your `API_SECRET`; sent as the `API-SECRET: sha1(secret)` header. Stored in the macOS Keychain, never in plain text.
- **Test Connection** — calls `/api/v1/status.json` and shows the result.
- **Units** — mg/dL or mmol/L.
- **Polling interval** — 30 s, 1, 2, or 5 min.
- **Default chart window** — 6 / 12 / 24 h.
- **Launch at login**, **show menu bar icon**, **Demo mode**.

### Alerts

Per category (urgent low, low, high, urgent high, rising fast, falling fast, stale data): enable toggle, threshold (in the selected unit), sound, plus global cooldown (default 20 min; 10 min for urgent), quiet hours, volume, and alert previews.

## Architecture

```
Package.swift
Sources/
  MacscoutCore/        testable logic, no UI
    Models.swift           GlucoseEntry, Treatment, DeviceStatus, TrendArrow, GlucoseUnit
    NightscoutClient.swift async REST client (token or api-secret auth, typed errors)
    AlertEngine.swift      threshold evaluation, cooldown/dedup, quiet hours
    AlertSettings.swift    Codable alert configuration (thresholds stored in mg/dL)
    StatsCalculator.swift  time-in-range, mean, GMI
    UnitConverter.swift    mg/dL ↔ mmol/L
    Chiptune.swift         chiptune cue + ceremony jingle synthesis (pure, tested)
  Macscout/            the app (SwiftUI + AppKit)
    App/ (main, AppDelegate, AppState, SettingsStore, AlertNotifier)
    Windows/ (NotchWindowController, MenuBarController, SpringFrameAnimator)
    Audio/ (SoundPlayer, ChiptunePlayer — plays the MacscoutCore-generated cues)
    Views/ (Design tokens + pixel font, NotchView, SparklineView, ExpandedPanelView,
            GlucoseChartView, StatsView, PixelIcons, SettingsView)
    Onboarding/ (OnboardingWindowController, OnboardingView, ConfettiView)
    Resources/ (Info.plist, AppIcon.icns — generated, Fonts/DepartureMono + OFL.txt)
  MacscoutCoreTestsRunner/  tiny helper executable used by the test harness
Tests/MacscoutCoreTests/
scripts/build.sh, scripts/make-icon.swift
```

### A note on the test harness

This project is buildable with **Command Line Tools only** (no Xcode). That toolchain ships neither XCTest nor a functional swift-testing runner, so `Tests/MacscoutCoreTests/TestHarness.swift` implements a tiny assertion harness that executes when SwiftPM loads the test bundle and fails `swift test` with a non-zero exit code on any failed check. The URLSession-based client tests run in a child process (`MacscoutCoreTestsRunner`, spawned by the harness) because CFNetwork cannot initialize inside a `dlopen` constructor.

## Roadmap

- [ ] Loop / pump data overlays
- [ ] Watch complication companion
- [ ] Multiple Nightscout profiles
- [ ] Widget / StandBy support
- [ ] Signed & notarized releases

## Contributing

PRs, issues, translations, and design polish are welcome — especially from the
#WeAreNotWaiting community.

- **[Contributing guide](.github/CONTRIBUTING.md)** — setup, branch names, what makes a good PR
- **[Pull request template](.github/pull_request_template.md)** — filled in automatically on new PRs
- **Bug** / **Feature** issue forms under *New issue*
- **[Code of Conduct](CODE_OF_CONDUCT.md)** · **[Security policy](SECURITY.md)**
- **[AGENTS.md](AGENTS.md)** — notes for coding agents working in this repo

```bash
swift test
./scripts/build.sh
open dist/Macscout.app
```

## The fun bits

The band carries one code-drawn pixel icon beside the reading. A pulsing blood
drop means you're in range; it turns into a yellow caution sign when you leave
the target range and a red one when things get urgent. And on magic numbers —
a diabetes-community tradition — the icon becomes a tiny celebration: hit
100 mg/dL and a unicorn shows up.

<p align="center">
  <img src="docs/images/special-icons.png" alt="Band status and magic-value pixel icons" width="700">
</p>

## Dedication

Dedicated to the **AndroidAPS community** and to my son, **George Benício Soares**. ❤️

Proudly part of the **#WeAreNotWaiting** movement — the DIY diabetes community
(Nightscout, AndroidAPS, Loop, OpenAPS) that builds the tools we need instead
of waiting for them.

## Author

Created by **Thiago Mota Soares** — if Macscout helps you, a ⭐ on GitHub and a follow on
Instagram ([@paipancreas](https://instagram.com/paipancreas)) make my day!

## Acknowledgements

- [Departure Mono](https://departuremono.com/) by Helena Zhang, bundled under the SIL Open Font License 1.1 (see `Sources/Macscout/Resources/Fonts/OFL.txt`).
- [Nightscout](https://nightscout.github.io/) — Macscout is an independent client and is not affiliated with the Nightscout project.

## License

[MIT](LICENSE) © [Thiago Mota Soares](https://github.com/thiagomsoares) and [Macscout contributors](https://github.com/thiagomsoares/macscout/graphs/contributors)

By contributing, you agree that your contributions are licensed under the MIT License.
