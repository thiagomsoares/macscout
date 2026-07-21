# AGENTS.md

Guidance for coding agents (and humans pairing with them) working on Macscout.

## Project in one breath

Macscout is a **macOS 14+** menu-bar / notch client for **Nightscout**. Pure
Swift 6, **zero third-party dependencies**, builds with Command Line Tools only
(no full Xcode required). MIT. English source strings + Português (Brasil).

## Layout

```
Sources/MacscoutCore/   # testable domain logic, no AppKit UI
Sources/Macscout/       # app: AppKit windows + SwiftUI views
Tests/MacscoutCoreTests/
scripts/                # build.sh, release.sh, make-icon.swift
docs/DESIGN.md          # color, type, motion, sound — source of truth
```

- Put pure logic in `MacscoutCore` and cover it with tests.
- Put UI / windowing in `Macscout`.
- Do not add Swift packages unless the user explicitly asks.

## Design

All visual / motion / sound work follows [`docs/DESIGN.md`](docs/DESIGN.md).

- Pixel face (Departure Mono) for glucose values and headline moments; SF Pro for body.
- Nightscout range colors are semantic — do not repurpose them for decoration.
- Stale readings must read as stale (gray + age). Urgent must stay urgent.
- Prefer synthesizing assets in code (chiptune, confetti, icon) over bundling binaries.

## Localization

- UI copy goes through `L("English key")` / `LF("English key %@", arg)`.
- The English key *is* the English string (no `en.lproj` table).
- Add `pt-BR` entries in `Sources/Macscout/Resources/pt-BR.lproj/Localizable.strings`
  in the same change when you introduce new user-facing text.

## Secrets & safety

- Nightscout token / API secret: **Keychain only** (`SettingsStore` / `Keychain`).
- Never log secrets, never write them to `UserDefaults`, never ship them in fixtures.
- Alert and freshness logic is safety-adjacent — prefer explicit tests over “looks fine”.
- Macscout is **not** a medical device; do not market or comment it as one.

## Build & test

```bash
swift test
swift build -c release --product Macscout
./scripts/build.sh          # dist/Macscout.app, ad-hoc signed
```

The test harness is custom (`Tests/MacscoutCoreTests/TestHarness.swift`) because
the CLT-only toolchain has no working XCTest / swift-testing runner. Match the
existing `register("Suite", …)` pattern when adding tests.

Networked client tests run in `MacscoutCoreTestsRunner` (child process). Keep
URLSession work out of `dlopen` constructors.

## Conventions

- Conventional commits: `fix:`, `feat:`, `docs:`, `chore:`, `test:`, `refactor:`.
- Comments explain **why**, briefly — not what the next line literally does.
- No vague module names (`helpers`, `utils`, `common`). Name files after the domain concept.
- Keep PRs focused. Update `docs/DESIGN.md` when you change the visual contract.
- Releases / version bumps / notarization are maintainer-owned.

## Do not

- Add analytics, crash reporters, or network calls to hosts other than the
  user's Nightscout site and (for updates) the GitHub Releases API.
- Weaken click-through / first-mouse / fullscreen notch behavior without a
  deliberate, documented reason.
- Commit `.env`, real site URLs with tokens, or personal health data.
- Rewrite the project into Xcode-only or SPM-heavy form without an explicit ask.

## When unsure

Read `README.md`, `docs/DESIGN.md`, and `.github/CONTRIBUTING.md` before inventing
process. Prefer a small correct change over a large speculative one.
