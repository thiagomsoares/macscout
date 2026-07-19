import SwiftUI

/// A tiny code-drawn pixel-art sprite: character rows map to palette colors
/// ('.' and ' ' are transparent). No image assets — everything is data.
struct PixelSprite: Equatable {
    let name: String
    let rows: [String]
    let palette: [Character: Color]
    /// Soft glow tint behind the sprite (phosphor-style).
    let glow: Color

    var gridWidth: Int { rows.map(\.count).max() ?? 0 }
    var gridHeight: Int { rows.count }

    static func == (lhs: PixelSprite, rhs: PixelSprite) -> Bool {
        lhs.name == rhs.name
    }
}

/// Renders a `PixelSprite` as crisp square pixels in a Canvas.
struct PixelIconView: View {
    let sprite: PixelSprite
    var pixelSize: CGFloat = 1.6

    var body: some View {
        Canvas { ctx, _ in
            for (r, row) in sprite.rows.enumerated() {
                for (c, ch) in row.enumerated() {
                    guard let color = sprite.palette[ch] else { continue }
                    let rect = CGRect(x: CGFloat(c) * pixelSize, y: CGFloat(r) * pixelSize,
                                      width: pixelSize, height: pixelSize)
                    ctx.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(sprite.gridWidth) * pixelSize,
               height: CGFloat(sprite.gridHeight) * pixelSize)
        .shadow(color: sprite.glow.opacity(0.6), radius: 3)
        .accessibilityHidden(true)
    }
}

/// The animated brand mark for the collapsed band: a pixel blood drop that
/// "beats" (~57 bpm) by swapping two frames, tinted with the current range
/// color. Classic two-frame sprite animation — no scaling, just pixels.
struct PulsingPixelIconView: View {
    let color: Color
    var pixelSize: CGFloat = 1.4

    private static let restRows = [
        "....R....",
        "....R....",
        "...RRR...",
        "...RRR...",
        "..RRRRR..",
        ".RRRRRRR.",
        ".RWRRRRR.",
        ".RWRRRRR.",
        "..RRRRR..",
        "...RRR...",
    ]
    private static let beatRows = [
        "....R....",
        "...RRR...",
        "...RRR...",
        "..RRRRR..",
        ".RRRRRRR.",
        "RRWRRRRRR",
        "RRWRRRRRR",
        ".RRRRRRR.",
        "..RRRRR..",
        "...RRR...",
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.15)) { ctx in
            let phase = ctx.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.05)
            let rows = phase < 0.15 ? Self.beatRows : Self.restRows
            PixelIconView(
                sprite: PixelSprite(name: "drop", rows: rows,
                                    palette: ["R": color, "W": Color(hex: 0xF4F4F8)],
                                    glow: color),
                pixelSize: pixelSize)
        }
    }
}

/// Special glucose values with their own pixel icon — a diabetes-community
/// tradition (a reading of 101 is a "unicorn"). Keys are whole mg/dL values,
/// matched against the current reading regardless of display unit.
enum SpecialGlucoseIcons {
    static func sprite(for mgdl: Double) -> PixelSprite? {
        table[Int(mgdl.rounded())]
    }

    // Shared palette inks.
    private static let white = Color(hex: 0xEDEDF2)
    private static let pink = Color(hex: 0xFF8FC7)
    private static let gold = Color(hex: 0xFFD34D)
    private static let dark = Color(hex: 0x1B1B22)
    private static let amber = Color(hex: 0xFB923C)
    private static let sky = Color(hex: 0x7DD3FC)
    private static let phosDim = Color(hex: 0x6B9679)
    private static let phosMid = Color(hex: 0x57C787)
    private static let phosBright = Color(hex: 0x7CF5A8)

    static let table: [Int: PixelSprite] = [
        // 100 — a perfect century: the unicorn.
        100: PixelSprite(
            name: "unicorn",
            rows: [
                "........Y...",
                ".......YY...",
                "....WW.Y....",
                "..PWWWWW....",
                ".PPWWWWWW...",
                ".PWWWWWKW...",
                ".PWWWWWWWWW.",
                "..PWWWWWWWW.",
                "...WWWWWW...",
                "...WW..WW...",
            ],
            palette: ["W": white, "P": pink, "Y": gold, "K": dark],
            glow: pink),

        // 101 — the dalmatian (101 of them, famously).
        101: PixelSprite(
            name: "dalmatian",
            rows: [
                "....KK......",
                "...KKK......",
                "..KKWWW.....",
                "..WWWWWW....",
                "..WWWWWKW...",
                "..WKWWWWWWW.",
                "..WWWWWWWWK.",
                "...WWWKWW...",
                "...WW..WW...",
            ],
            palette: ["W": white, "K": dark],
            glow: white),

        // 111 — three candles: make a wish.
        111: PixelSprite(
            name: "candles",
            rows: [
                ".Y..Y..Y.",
                ".Y..Y..Y.",
                ".W..W..W.",
                ".W..W..W.",
                ".W..W..W.",
                ".W..W..W.",
                "GGGGGGGGG",
            ],
            palette: ["Y": gold, "W": white, "G": phosMid],
            glow: gold),

        // 123 — easy as 1-2-3: rising steps.
        123: PixelSprite(
            name: "steps",
            rows: [
                "........GG",
                "........GG",
                "....MM..GG",
                "....MM..GG",
                "DD..MM..GG",
                "DD..MM..GG",
            ],
            palette: ["D": phosDim, "M": phosMid, "G": phosBright],
            glow: phosBright),

        // 222 — a little duck (a 2 is a duck).
        222: PixelSprite(
            name: "duck",
            rows: [
                ".....YY..",
                "....YYYY.",
                "....YYYO.",
                ".YYYYYY..",
                "YYYYYYY..",
                ".YYYYY...",
            ],
            palette: ["Y": gold, "O": amber],
            glow: gold),

        // 314 — pi day, every day.
        314: PixelSprite(
            name: "pi",
            rows: [
                "BBBBBBBBB",
                "..BB..BB.",
                "..BB..BB.",
                "..BB..BB.",
                ".BB...BBB",
            ],
            palette: ["B": sky],
            glow: sky),

    ]
}

/// Range-status icons for the collapsed band: a pixel warning sign shown when
/// the reading leaves the target range (yellow) or goes urgent (red).
enum StatusIcons {
    private static let cautionRows = [
        ".....Y.....",
        "....YYY....",
        "....YKY....",
        "...YYKYY...",
        "...YYKYY...",
        "..YYYKYYY..",
        "..YYYYYYY..",
        ".YYYYKYYYY.",
        "YYYYYYYYYYY",
    ]
    private static let ink = Color(hex: 0x1B1B22)

    static let cautionOutOfRange = PixelSprite(
        name: "caution-yellow", rows: cautionRows,
        palette: ["Y": Color(hex: 0xFACC15), "K": ink],
        glow: Color(hex: 0xFACC15))

    static let cautionUrgent = PixelSprite(
        name: "caution-red", rows: cautionRows,
        palette: ["Y": Color(hex: 0xEF4444), "K": ink],
        glow: Color(hex: 0xEF4444))
}
