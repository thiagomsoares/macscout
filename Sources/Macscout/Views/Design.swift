import AppKit
import CoreText
import SwiftUI

// Design tokens from docs/DESIGN.md.

extension NSColor {
    /// Hex RGB initializer (0xRRGGBB).
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    /// Hex RGB initializer (0xRRGGBB).
    init(hex: UInt32, alpha: Double = 1) {
        self.init(nsColor: NSColor(hex: hex, alpha: alpha))
    }
}

/// Design-system color tokens (docs/DESIGN.md — "Foundations").
enum DSColors {
    static let inRange = NSColor(hex: 0x4ADE80)
    static let low = NSColor(hex: 0xF87171)
    static let urgentLow = NSColor(hex: 0xEF4444)
    static let high = NSColor(hex: 0xFACC15)
    static let urgentHigh = NSColor(hex: 0xFB923C)
    static let stale = NSColor(hex: 0x9CA3AF)
    static let accent = NSColor(hex: 0xE8483F)
    static let card = NSColor(hex: 0x0E0E13)
    static let canvas = NSColor(hex: 0x050507)
    static let stroke = NSColor.white.withAlphaComponent(0.08)
    static let textSecondary = NSColor.white.withAlphaComponent(0.6)

    // Green-phosphor "pixel CRT" theme (expanded panel).
    static let phosphorBg = NSColor(hex: 0x071109)
    static let phosphorDim = NSColor(hex: 0x6B9679)
    static let phosphorBright = NSColor(hex: 0x7CF5A8)
    static let phosphorPale = NSColor(hex: 0xD9FBE7)
}

extension Color {
    static let dsInRange = Color(nsColor: DSColors.inRange)
    static let dsLow = Color(nsColor: DSColors.low)
    static let dsUrgentLow = Color(nsColor: DSColors.urgentLow)
    static let dsHigh = Color(nsColor: DSColors.high)
    static let dsUrgentHigh = Color(nsColor: DSColors.urgentHigh)
    static let dsStale = Color(nsColor: DSColors.stale)
    static let dsAccent = Color(nsColor: DSColors.accent)
    static let dsCard = Color(nsColor: DSColors.card)
    static let dsCanvas = Color(nsColor: DSColors.canvas)
    static let dsPhosphorBg = Color(nsColor: DSColors.phosphorBg)
    static let dsPhosphorDim = Color(nsColor: DSColors.phosphorDim)
    static let dsPhosphorBright = Color(nsColor: DSColors.phosphorBright)
    static let dsPhosphorPale = Color(nsColor: DSColors.phosphorPale)
}

/// The bundled pixel face (Departure Mono, SIL OFL — Resources/Fonts).
enum PixelFont {
    static let familyName = "Departure Mono"
    private(set) static var available = false

    /// Registers bundled fonts with Core Text; defensive when the font file
    /// is missing (dev runs outside the .app bundle).
    static func register() {
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
            // Dev runs straight from .build: Resources live next to Sources.
            Bundle.main.bundleURL.deletingLastPathComponent()
                .appendingPathComponent("Fonts"),
        ]
        for directory in candidates.compactMap({ $0 }) {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension.lowercased() == "otf" {
                if CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil) {
                    available = true
                }
            }
            if available { return }
        }
        if !available {
            NSLog("Macscout: pixel font not found, falling back to monospaced system font")
        }
    }
}

extension Font {
    /// Pixel display face (Departure Mono), crisp at multiples of 11 pt;
    /// falls back to monospaced system when the bundled font is unavailable.
    static func pixel(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if PixelFont.available {
            return .custom(PixelFont.familyName, size: size)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }
}

/// CRT tube treatment: faint horizontal scanlines plus an edge vignette.
/// Layered *above* content (hit-testing disabled) so the glow, text and dots
/// all sit "behind the glass". Pure drawing — no timers, no animation.
struct CRTScreenEffect: View {
    var scanlineOpacity: Double = 0.07
    var vignetteOpacity: Double = 0.22

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                var y: CGFloat = 1
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                             with: .color(.black.opacity(scanlineOpacity)))
                    y += 3
                }
            }
            RadialGradient(colors: [.clear, .black.opacity(vignetteOpacity)],
                           center: .center, startRadius: 120, endRadius: 460)
        }
        .allowsHitTesting(false)
    }
}
