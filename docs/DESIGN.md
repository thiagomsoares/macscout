# Macscout Design System

The style guide and motion/sound spec for Macscout.

## Design pillars

- **Pixel typography as identity** — a pixel monospace face (Departure Mono, SIL OFL) for
  display values and headline moments; system font for body copy.
- **The pill is the brand** — the app icon is literally the notch pill; the pill glows,
  bounces and "lands" in the notch during onboarding so the user learns where it lives.
- **Onboarding as a story in acts** — fullscreen synthesized backdrop + centered card,
  acts with per-act transitions, a *live demo running in the real notch UI* during the
  pitch, and a closing "ceremony": confetti + a short music cue.
- **8-bit sound design, synthesized in code** — a chiptune engine generates the
  cues per event (no large audio assets).
- **Motion vocabulary** — rotating glow highlights, spring-like expand/collapse,
  auto-reveal with dwell.

## Macscout principles

1. **Glanceable above all** — the pill must read at 1 m distance in 200 ms.
2. **Alive, never noisy** — motion and sound celebrate and warn, then get out of the way.
3. **Zero binary assets where code can generate** — sounds and wallpapers are synthesized;
   the only bundled asset is the OFL font and the app icon.

## Foundations

### Color (on pure black `#050507`)

| Token | Value | Use |
|---|---|---|
| `inRange` | `#4ADE80` (green) | glucose in target range |
| `low` | `#F87171` (red) | below range |
| `urgentLow` | `#EF4444` + pulse | urgent low |
| `high` | `#FACC15` (yellow) | above range |
| `urgentHigh` | `#FB923C` (orange) | urgent high |
| `stale` | `#9CA3AF` (gray) | no recent data |
| `accent` | `#E8483F` (blood red) | brand, chart accents, CTA |
| `card` | `#0E0E13` | legacy card tone (chrome is pure black today) |
| `stroke` | white 8% | hairlines |
| `textPrimary` / `textSecondary` | white / white 60% | — |
| `phosphorBg` | `#071109` | CRT green-black (tooltip fills) |
| `phosphorDim` | `#6B9679` | secondary phosphor text, axis labels |
| `phosphorBright` | `#7CF5A8` | highlights, tips, headings glow |
| `phosphorPale` | `#D9FBE7` | treatment markers, hover line |

### Typography

- **Display / glucose values / headlines:** Departure Mono (SIL OFL, by Helena Zhang —
  bundled from the official repo with license in `Resources/Fonts/OFL.txt`).
  In use: band value 14 / trend & delta 10; panel value 44 / arrow 22 / labels 11;
  onboarding title 33 / act titles 22.
- **Body / labels / settings:** SF Pro (system), regular/medium; stat labels are
  8 pt uppercase with tracking (SF only — never letter-space the pixel font).

### Shape

- Collapsed band: 365×32 — notch footprint (185, from the macOS API) plus a 90pt
  content "ear" on each side. Contour = `NotchBandShape`, a two-radius model
  (`topCornerRadius` / `bottomCornerRadius`): concave 6pt top
  ears melting out of the menu bar, convex 13pt bottom corners, faint white
  hairline along the contour. On no-notch screens the floating pill drops the
  concave ears (top radius 0). The camera cutout blends the middle. Content anchors to the band's outer edges
  (text ≈ 1/3 of the band height): left ear = animated
  pixel blood-drop (two-frame ~57 bpm beat, tinted by range color) + value
  (pixel 14) + trend (pixel 10); right ear = delta (pixel 10) + 12 h pixel dot
  trail. Special-value icons appear beside the drop.
- Expanded panel: 700×380 default, same `NotchBandShape` family as the band
  (concave 6pt top ears, convex 16pt bottom corners), top edge flush with the
  screen. Same chrome as the band: pure black background, faint white
  hairline (12%) along the contour — the phosphor green lives in the content,
  not the frame.
- Onboarding card: 620×560, radius 20, over a fullscreen synthesized backdrop
  (dark rays gradient in `accent`/black — generated, not a bitmap).

### Charts (green-phosphor dot matrix)

The panel chart is a **dot matrix**: a uniform grid of round green dots
(pitch 8 pt, radius 2.4 pt — diameter/pitch ≈ 0.6) stacked from the baseline
up to each reading, forming the curve's silhouette. Columns fade with age
(oldest ≈ 35%, latest 100%); the top dot of each column is the brighter
`phosphorBright` tip. Pixel-dotted threshold lines with pixel labels, 6%
target band, pale treatment markers: carbs float as triangles above the plot;
insulin lives in a dedicated lane just below it (clearly separated from the
matrix), dose-weighted — opacity 0.4→1.0 and radius 2.6→4.2 pt scale with the
dose (saturating at 4 U / 6 U), labels only from 1 U up so AID microboluses
stay quiet. Hovering shows a dashed line + tooltip for readings, insulin doses
(exact to 0.01 U) and carbs. Entries are fetched by a 24 h server-side window
(`find[date][$gte]`), so 1-min AID uploaders still fill the full chart.
Chart window floor is 6 h (options 6/12/24). Cells with no reading within 10 min stay empty —
honest gaps. Out-of-range readings turn semantic in the matrix: dots poking
above the high threshold go yellow (`high`), and a below-range reading paints
its whole short column red (`low`) — tips take the same color, brighter.
The collapsed-band sparkline speaks the same language in
miniature: a 12 h dot trail (46×18 pt, pitch 2.6), one dot per time column at the
reading's height, fading with age, white tip for the latest reading.
Range colors appear only where they carry alert semantics (pill value, header
value, out-of-range chart dots, TIR bar, alert banners). The menu bar item
uses the system label color, like any native status item.

### Band status icon (collapsed band)

One pixel-art icon slot beside the value, all drawn in code (no assets).
Range state decides what shows; urgent always wins over a fun sprite:

| State | Icon |
|---|---|
| in range | pulsing green blood drop (the brand mark) |
| below / above target | yellow pixel caution sign |
| urgent low / urgent high | red pixel caution sign |
| stale | gray pulsing drop (plus the "!" by the value) |

Magic values (community tradition; matched on the whole-mg/dL reading, shown
unless the reading is urgent):

| mg/dL | Icon |
|---|---|
| 100 | unicorn (perfect century) |
| 101 | dalmatian (101 of them) |
| 111 | three candles |
| 123 | rising steps |
| 222 | duck |
| 314 | π |

## Motion spec

| Moment | Curve | Duration | Notes |
|---|---|---|---|
| Panel expand | spring `response 0.40, damping 0.70` | settles ≈0.36 s | lively ~5% overshoot. Content enters as a staggered cascade — header → chart → stats → footer, each rising + fading over 0.3 s with 0.05 s between beats — while the frame spring travels. Hand-tuned: a clearly visible pop that settles ≈250 ms after the peak |
| Panel collapse | spring `response 0.34, damping 0.85` | settles ≈0.30 s | exits are quicker and drier — no bounce |
| Hover delays | — | in 0.12 s / out 0.35 s | the ≈1/3 s leave-grace lets the pointer travel from the band into the panel |
| Pill glow (onboarding, urgent) | linear rotation | 2.5 s loop | angular gradient stroke + soft shadow |
| Pill "landing" (onboarding end) | spring `response 0.5, damping 0.6` + corner bounce | — | scale 1→1.12→1 |
| New reading on the band | spring pop | 0.2 s up / 0.3 s down | value scale 1→1.18→1 |
| Alert reveal | ease-out slide + fade | 0.25 s | auto-collapse after dwell (6 s, urgent: sticky) |
| Onboarding act transitions | asymmetric move + opacity | 0.35 s | forward: from below; back: from above |

## Sound spec (all synthesized at runtime, AVAudioEngine square/triangle waves)

| Event | Cue |
|---|---|
| Urgent low | descending 3-note minor arpeggio, repeats until acked (cooldown) |
| Low | two low square blips |
| High | two rising triangle blips |
| Urgent high | ascending 3-note arpeggio |
| Stale data | single muted tick |
| Ceremony (onboarding complete) | ~5 s chiptune jingle (I–V–vi–IV, square lead + triangle bass), played at 35% of the alert volume |
| Quiet hours / Focus | all cues muted (visual only) |

## Onboarding v2 (implemented on this spec)

Fullscreen synthesized rays backdrop + 620×560 card, 5 acts (Welcome → Story →
Connect → Alerts → Finish). Shared skeleton: content anchors to the top with a
consistent rhythm (ceremonial acts 1 and 5 center themselves); acts 2–4 open
with an "ACT N OF 5" eyebrow + pixel title. Pixel progress dots in the footer
(active dot stretches into a phosphor bar). Story beats sit in colored icon
tiles; a live-demo callout carries the pulsing brand drop. The demo escape
hatch lives in the Connect flow (phosphor link → "✓ using demo data" state).
Live demo data runs in the notch throughout; the connection test renders a
real reading inside the card. Ceremony = confetti burst from the top of the
card (deferred until layout so it never fires from a corner) + jingle at 35%
of the alert volume + pill landing bounce. `hasCompletedOnboarding` persisted;
replay from Settings → About.

## Localization

English and Português (Brasil). Keys are the English copy (missing translations
fall back to the key); pt-BR lives in `Resources/pt-BR.lproj/Localizable.strings`.
Default mode follows the system language, with a manual picker in
Settings → Display → Language; switching re-resolves the bundle live and
rebuilds every visible surface. Alert messages are unit-aware
(mg/dL / mmol/L) and localized at the display layer — Core stays English.

## Icon

Black pill on dark rounded square containing a pixel-art blood drop + glucose trace —
the pill *is* the brand. Generated by `scripts/make-icon.swift`.
