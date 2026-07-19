import AVFoundation
import Foundation
import MacscoutCore

/// Plays the synthesized 8-bit cues (Chiptune engine, MacscoutCore) via
/// AVAudioPlayer. Rendered WAV data is cached per cue.
@MainActor
final class ChiptunePlayer {
    private var cache: [AlertKind: Data] = [:]
    private var ceremonyData: Data?
    private var player: AVAudioPlayer?

    /// Plays the cue for an alert category. Urgent-low repeats (spec: the
    /// arpeggio re-sounds while unacknowledged — bounded to 3 plays; the
    /// alert cooldown governs further repeats).
    func playCue(for kind: AlertKind, volume: Float) {
        let data = cache[kind] ?? {
            let rendered = Chiptune.renderWAV(events: Chiptune.cue(for: kind))
            cache[kind] = rendered
            return rendered
        }()
        play(data, volume: volume, loops: kind == .urgentLow ? 2 : 0)
    }

    /// The ~5 s onboarding ceremony jingle. Attenuated well below the alert
    /// volume: alerts must be loud enough to wake you, but the celebration
    /// jingle (dense, peak-normalized lead + bass) at that level is startling.
    func playCeremony(volume: Float) {
        let data = ceremonyData ?? {
            let rendered = Chiptune.renderWAV(events: Chiptune.ceremonyJingle)
            ceremonyData = rendered
            return rendered
        }()
        play(data, volume: volume * 0.35, loops: 0)
    }

    private func play(_ data: Data, volume: Float, loops: Int) {
        do {
            player?.stop()
            let audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer.volume = max(0, min(1, volume))
            audioPlayer.numberOfLoops = loops
            audioPlayer.prepareToPlay()
            player = audioPlayer
            audioPlayer.play()
        } catch {
            NSLog("Macscout: synthesized sound playback failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        player?.stop()
    }
}
