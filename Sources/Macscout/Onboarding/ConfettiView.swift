import AppKit
import QuartzCore
import SwiftUI

/// Confetti burst overlay (CAEmitterLayer wrapped in NSViewRepresentable).
struct ConfettiView: NSViewRepresentable {
    /// When true, a burst is emitted.
    let trigger: Bool

    func makeNSView(context: Context) -> ConfettiEmitterView {
        ConfettiEmitterView()
    }

    func updateNSView(_ nsView: ConfettiEmitterView, context: Context) {
        if trigger { nsView.burst() }
    }
}

/// NSView hosting a CAEmitterLayer that fires one confetti burst per `burst()` call.
final class ConfettiEmitterView: NSView {
    private let emitter = CAEmitterLayer()
    private var burstToken = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(emitter)
        configureEmitter()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        emitter.frame = layer?.bounds ?? .zero
        // Layer geometry is y-up: 0.9 × height = near the top of the card.
        emitter.emitterPosition = CGPoint(x: (layer?.bounds.midX ?? 0),
                                          y: (layer?.bounds.height ?? 0) * 0.9)
        emitter.emitterSize = CGSize(width: (layer?.bounds.width ?? 0) * 0.7, height: 1)
        CATransaction.commit()
    }

    private func configureEmitter() {
        emitter.emitterShape = .line
        emitter.renderMode = .oldestLast
        emitter.birthRate = 0
        emitter.emitterCells = Self.colors.map { makeCell(color: $0) }
    }

    private static let colors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemMint, .systemBlue, .systemPurple, .systemPink,
    ]

    private func makeCell(color: NSColor) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.birthRate = 8
        cell.lifetime = 3.0
        cell.velocity = 160
        cell.velocityRange = 120
        cell.yAcceleration = -260
        cell.emissionLongitude = -.pi / 2 // downward (y-up layer geometry)
        cell.emissionRange = .pi / 5
        cell.spin = 3
        cell.spinRange = 5
        cell.scale = 0.6
        cell.scaleRange = 0.3
        cell.contents = Self.particleImage(color: color)
        return cell
    }

    /// Small rounded-square particle image.
    private static func particleImage(color: NSColor) -> CGImage? {
        let size = NSSize(width: 8, height: 10)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Fire a burst: emit for a short window, then let particles fall out.
    /// Deferred until the view has real bounds — bursting before the first
    /// layout pass would emit from (0,0), i.e. the bottom-left corner.
    func burst() {
        guard bounds.width > 1 else {
            DispatchQueue.main.async { [weak self] in self?.burst() }
            return
        }
        burstToken += 1
        let token = burstToken
        emitter.birthRate = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.burstToken == token else { return }
            self.emitter.birthRate = 0
        }
    }
}
