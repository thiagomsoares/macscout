# Contributing to Macscout

Thanks for wanting to help. Macscout is a small, dependency-free macOS app that
puts Nightscout glucose in the MacBook notch. Contributions of every size are
welcome — bug reports, design polish, docs, translations, and code.

This guide is intentionally short. If something is missing, open an issue and
we'll fill the gap.

## Before you start

- Keep each change focused on one user-visible improvement, bug fix, or refactor.
- Macscout is **macOS 14+ only**, pure Swift 6, **zero third-party packages**.
  Prefer Foundation / AppKit / SwiftUI / Swift Charts over new dependencies.
- Logic that can live without UI belongs in `MacscoutCore` (and gets tests).
  UI lives in `Macscout`.
- Follow the existing design system in [`docs/DESIGN.md`](../docs/DESIGN.md) —
  colors, type, motion, and sound are specified there. Don't invent parallel
  tokens when a documented one already covers the role.
- This is diabetes tooling used at a glance. Prefer clarity and safety over
  cleverness: never hide a stale reading, never soften an urgent color, never
  store secrets outside the Keychain.
- English is the source language for UI strings (the key *is* the English copy).
  Português (Brasil) lives in `Sources/Macscout/Resources/pt-BR.lproj/Localizable.strings`.
  If you add user-facing text, add the `pt-BR` entry in the same PR when you can.

## Local setup

```bash
# macOS 14+, Swift 6.2+ toolchain (Xcode Command Line Tools are enough)
git clone https://github.com/thiagomsoares/macscout.git
cd macscout

swift test                              # full suite
swift build -c release --product Macscout
./scripts/build.sh                      # → dist/Macscout.app (ad-hoc signed)
open dist/Macscout.app
```

Full Xcode is **not** required. See the README architecture note for why the
test harness is custom (CLT-only toolchain).

### Useful scripts

| Script | What it does |
|---|---|
| `scripts/build.sh` | Release build + `dist/Macscout.app` + ad-hoc sign |
| `scripts/make-icon.swift` | Regenerates `AppIcon.icns` from code |
| `scripts/release.sh` | Builds the versioned DMG under `dist/` |

## Branch naming

Use a clear, descriptive name:

- `fix/stale-badge-not-clearing`
- `feat/mmol-delta-precision`
- `docs/contributing-guide`
- `chore/tighten-alert-cooldown-tests`

Avoid `fix`, `misc`, `updates`, `wip`.

## What makes a good change

**Great fits**

- Bug fixes with a regression test in `MacscoutCore` when possible
- Glanceability / motion / accessibility polish that respects `docs/DESIGN.md`
- Nightscout API edge cases, unit conversion, alert engine behavior
- pt-BR (or new locale) coverage for existing strings
- Docs that help the next contributor

**Ask first (open an issue)**

- New networking / cloud services
- New third-party dependencies
- Changes to the on-disk settings schema or Keychain accounts
- Anything that could affect medical safety of readings or alerts
- Large visual redesigns of the band or panel

**Out of scope for drive-by PRs**

- Version bumps / release tags (maintainer-managed)
- Rewrites that drop the “zero dependencies / CLT-only build” constraints
- Changes that require a paid Apple Developer account to even run

## Before opening a PR

```bash
swift test
./scripts/build.sh
open dist/Macscout.app   # smoke-test the path you touched
```

Checklist:

- [ ] `swift test` is green
- [ ] Behavior changes in `MacscoutCore` have tests that would catch a regression
- [ ] New UI strings use `L("…")` / `LF("…", …)` and have a `pt-BR` entry when practical
- [ ] Design changes match [`docs/DESIGN.md`](../docs/DESIGN.md) (or update that doc in the same PR)
- [ ] No secrets, tokens, or real Nightscout URLs committed
- [ ] PR description explains the **user-visible** change

## Pull requests

1. Fork the repo (or push a branch, if you have write access).
2. Create a focused branch from `main`.
3. Make the change + tests/docs.
4. Open a PR against `main` using the PR template.
5. Keep the PR updated if `main` moves; rebase or merge as you prefer.

Each PR should:

- Explain the user-visible change in plain language
- Stay on one topic when possible (split big work)
- Include a screenshot or short recording for UI / motion changes  
  (or write `No visual change` explicitly)
- Call out macOS-version or hardware-notch assumptions you relied on
- Mention how you tested (demo mode, real Nightscout, both)

Draft PRs are welcome for early feedback.

## Reporting bugs & proposing features

Use the issue templates:

- **Bug report** — what broke, how to reproduce, macOS version, Macscout version
- **Feature request** — the problem / use case first, then a proposed solution

Security-sensitive reports go through [SECURITY.md](../SECURITY.md), not a public issue.

## Code of conduct

Be kind. This project serves people managing diabetes — including kids and
caregivers. Disrespect, harassment, or gatekeeping is not welcome. See
[CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md).

## License

By contributing, you agree that your contributions are licensed under the
project's [MIT License](../LICENSE).
