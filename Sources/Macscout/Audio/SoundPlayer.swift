import AppKit
import MacscoutCore

/// Plays alert sounds: the synthesized 8-bit cues (default) or macOS system
/// sounds, honoring volume and quiet-hours mute.
@MainActor
final class SoundPlayer {
    private var current: NSSound?
    private let synthesizer = ChiptunePlayer()

    func play(_ sound: SystemSoundName, for kind: AlertKind, volume: Float, muted: Bool) {
        guard !muted, sound != .none else { return }
        if sound == .chiptune {
            synthesizer.playCue(for: kind, volume: volume)
            return
        }
        guard let nsSound = NSSound(named: NSSound.Name(sound.rawValue)) else { return }
        current?.stop()
        nsSound.volume = max(0, min(1, volume))
        current = nsSound
        nsSound.play()
    }

    /// The onboarding ceremony jingle (always synthesized).
    func playCeremony(volume: Float) {
        synthesizer.playCeremony(volume: volume)
    }
}
