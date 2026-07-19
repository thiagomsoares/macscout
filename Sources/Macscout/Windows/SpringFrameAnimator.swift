import AppKit
import QuartzCore

/// Drives an NSWindow frame with a physically-based spring
/// (docs/DESIGN.md motion spec, hand-tuned on device).
/// CADisplayLink-synced; always completes with an exact final-frame snap.
@MainActor
final class SpringFrameAnimator: NSObject {
    private var displayLink: CADisplayLink?
    private var target = NSRect.zero
    private var current = NSRect.zero
    private var velocity = CGSize.zero // per-component velocity packed x,y / w,h pairs below
    private var velocitySize = CGSize.zero
    private var lastTimestamp: CFTimeInterval = 0
    private var elapsed: CFTimeInterval = 0
    private var onFrame: ((NSRect) -> Void)?
    private var onComplete: (() -> Void)?

    /// Hard cap so a stuck animation can never wedge the window.
    private let maxDuration: CFTimeInterval = 1.2

    struct Spring {
        let stiffness: CGFloat
        let damping: CGFloat

        init(response: Double, dampingFraction: Double) {
            let omega = 2 * .pi / response
            stiffness = omega * omega
            damping = 2 * dampingFraction * omega
        }

        /// Expansion: lively overshoot (~5%), settles in ≈0.36 s — a visible
        /// pop that lands quickly.
        static let expand = Spring(response: 0.40, dampingFraction: 0.70)
        /// Collapse: quicker and drier — exits shouldn't bounce.
        static let collapse = Spring(response: 0.34, dampingFraction: 0.85)
    }

    private var spring = Spring.expand

    func animate(view: NSView, from: NSRect, to: NSRect, spring: Spring = .expand,
                 onFrame: @escaping (NSRect) -> Void, onComplete: (() -> Void)? = nil) {
        stop()
        self.spring = spring
        current = from
        target = to
        velocity = .zero
        velocitySize = .zero
        elapsed = 0
        lastTimestamp = 0
        self.onFrame = onFrame
        self.onComplete = onComplete

        let link = view.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let dt: CFTimeInterval
        if lastTimestamp == 0 {
            dt = link.duration
        } else {
            dt = min(link.timestamp - lastTimestamp, 1.0 / 30) // clamp tab-switch gaps
        }
        lastTimestamp = link.timestamp
        elapsed += dt

        current.origin.x = integrate(current.origin.x, target: target.origin.x,
                                     v: &velocity.width, dt: dt)
        current.origin.y = integrate(current.origin.y, target: target.origin.y,
                                     v: &velocity.height, dt: dt)
        current.size.width = integrate(current.size.width, target: target.size.width,
                                       v: &velocitySize.width, dt: dt)
        current.size.height = integrate(current.size.height, target: target.size.height,
                                        v: &velocitySize.height, dt: dt)
        onFrame?(current)

        if settled() || elapsed >= maxDuration {
            onFrame?(target) // exact final-frame snap
            let completion = onComplete
            stop()
            onFrame = nil
            onComplete = nil
            completion?()
        }
    }

    private func integrate(_ value: CGFloat, target: CGFloat, v: inout CGFloat, dt: CFTimeInterval) -> CGFloat {
        let force = -spring.stiffness * (value - target) - spring.damping * v
        v += force * dt
        return value + v * dt
    }

    private func settled() -> Bool {
        let positionClose = abs(current.origin.x - target.origin.x) < 0.5
            && abs(current.origin.y - target.origin.y) < 0.5
            && abs(current.size.width - target.size.width) < 0.5
            && abs(current.size.height - target.size.height) < 0.5
        let velocityClose = abs(velocity.width) < 0.5 && abs(velocity.height) < 0.5
            && abs(velocitySize.width) < 0.5 && abs(velocitySize.height) < 0.5
        return positionClose && velocityClose
    }
}
