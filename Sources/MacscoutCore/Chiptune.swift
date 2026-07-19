import Foundation

/// Oscillator waveform for the chiptune engine.
public enum Waveform: Sendable {
    case square
    case triangle
}

/// Short ADSR envelope (seconds; sustain is a 0–1 level).
public struct ADSREnvelope: Sendable {
    public var attack: Double
    public var decay: Double
    public var sustain: Double
    public var release: Double

    public init(attack: Double = 0.008, decay: Double = 0.04, sustain: Double = 0.75, release: Double = 0.05) {
        self.attack = attack
        self.decay = decay
        self.sustain = sustain
        self.release = release
    }

    /// Envelope gain at `t` seconds into a note of `duration` seconds.
    public func gain(at t: Double, duration: Double) -> Double {
        if t < attack { return attack > 0 ? t / attack : 1 }
        let t2 = t - attack
        if t2 < decay {
            return 1 - (1 - sustain) * (decay > 0 ? t2 / decay : 0)
        }
        let releaseStart = max(attack + decay, duration - release)
        if t >= releaseStart {
            let progress = release > 0 ? (t - releaseStart) / release : 1
            return sustain * max(0, 1 - progress)
        }
        return sustain
    }
}

/// One scheduled note.
public struct NoteEvent: Sendable {
    public let frequency: Double
    /// Start offset in seconds from cue begin.
    public let start: Double
    public let duration: Double
    public let waveform: Waveform
    /// 0–1 note volume.
    public let volume: Double
    public let envelope: ADSREnvelope

    public init(frequency: Double, start: Double, duration: Double,
                waveform: Waveform, volume: Double = 0.5, envelope: ADSREnvelope = ADSREnvelope()) {
        self.frequency = frequency
        self.start = start
        self.duration = duration
        self.waveform = waveform
        self.volume = volume
        self.envelope = envelope
    }
}

/// Pure 8-bit sound synthesis: square/triangle oscillators with ADSR
/// envelopes, mixed and packaged as 44.1 kHz 16-bit mono WAV `Data`.
/// No audio assets anywhere — every cue is generated in code.
public enum Chiptune {
    public static let sampleRate = 44100

    /// MIDI note number → frequency in Hz (A4 = 69 = 440 Hz).
    public static func frequency(midi: Int) -> Double {
        440.0 * pow(2.0, Double(midi - 69) / 12.0)
    }

    /// Oscillator value in [-1, 1] at phase `t * frequency` cycles.
    public static func oscillator(_ waveform: Waveform, at time: Double, frequency: Double) -> Double {
        let phase = (time * frequency).truncatingRemainder(dividingBy: 1)
        switch waveform {
        case .square:
            return phase < 0.5 ? 1 : -1
        case .triangle:
            // 0→1 ramp up, 1→0 ramp down, centered on 0.
            return phase < 0.5 ? (phase * 4 - 1) : (3 - phase * 4)
        }
    }

    /// Renders events to signed 16-bit PCM samples (mono), soft-normalized
    /// so overlapping notes never clip.
    public static func renderPCM(events: [NoteEvent], sampleRate: Int = Chiptune.sampleRate) -> [Int16] {
        guard let last = events.map({ $0.start + $0.duration }).max(), last > 0 else { return [] }
        let count = Int((last * Double(sampleRate)).rounded(.up)) + 1
        var mix = [Double](repeating: 0, count: count)
        for event in events {
            let startIndex = Int(event.start * Double(sampleRate))
            let noteSamples = Int(event.duration * Double(sampleRate))
            for i in 0..<noteSamples {
                let t = Double(i) / Double(sampleRate)
                let gain = event.envelope.gain(at: t, duration: event.duration)
                mix[startIndex + i] += oscillator(event.waveform, at: t, frequency: event.frequency)
                    * gain * event.volume
            }
        }
        let peak = mix.map { abs($0) }.max() ?? 1
        let scale = peak > 1 ? 1 / peak : 1
        return mix.map { Int16((max(-1, min(1, $0 * scale)) * Double(Int16.max)).rounded()) }
    }

    /// 44-byte RIFF/WAVE header + PCM payload.
    public static func wavData(pcm: [Int16], sampleRate: Int = Chiptune.sampleRate) -> Data {
        let dataSize = UInt32(pcm.count * 2)
        var data = Data()
        func ascii(_ s: String) { data.append(contentsOf: s.utf8) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }

        ascii("RIFF"); u32(36 + dataSize); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(1)               // PCM, mono
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)) // rate, byte rate
        u16(2); u16(16)                                      // block align, bits
        ascii("data"); u32(dataSize)
        for sample in pcm { u16(UInt16(bitPattern: sample)) }
        return data
    }

    /// Convenience: events straight to WAV.
    public static func renderWAV(events: [NoteEvent], sampleRate: Int = Chiptune.sampleRate) -> Data {
        wavData(pcm: renderPCM(events: events, sampleRate: sampleRate), sampleRate: sampleRate)
    }

    // MARK: - Cue table (docs/DESIGN.md — Sound spec)

    /// The alert cue for a category.
    public static func cue(for kind: AlertKind) -> [NoteEvent] {
        switch kind {
        case .urgentLow:
            // Descending 3-note minor arpeggio (A4 → F4 → C4).
            return [69, 65, 60].enumerated().map { index, midi in
                NoteEvent(frequency: frequency(midi: midi), start: Double(index) * 0.16,
                          duration: 0.22, waveform: .square, volume: 0.5)
            }
        case .low:
            // Two low square blips.
            return [0.0, 0.18].map { start in
                NoteEvent(frequency: frequency(midi: 48), start: start,
                          duration: 0.10, waveform: .square, volume: 0.45)
            }
        case .high:
            // Two rising triangle blips.
            return [76, 81].enumerated().map { index, midi in
                NoteEvent(frequency: frequency(midi: midi), start: Double(index) * 0.18,
                          duration: 0.11, waveform: .triangle, volume: 0.6)
            }
        case .urgentHigh:
            // Ascending 3-note arpeggio (C4 → E4 → G4).
            return [60, 64, 67].enumerated().map { index, midi in
                NoteEvent(frequency: frequency(midi: midi), start: Double(index) * 0.14,
                          duration: 0.20, waveform: .square, volume: 0.5)
            }
        case .risingFast:
            return [0.0, 0.10].enumerated().map { index, start in
                NoteEvent(frequency: frequency(midi: 72 + index * 4), start: start,
                          duration: 0.08, waveform: .triangle, volume: 0.5)
            }
        case .fallingFast:
            return [0.0, 0.10].enumerated().map { index, start in
                NoteEvent(frequency: frequency(midi: 76 - index * 4), start: start,
                          duration: 0.08, waveform: .triangle, volume: 0.5)
            }
        case .staleData:
            // Single muted tick.
            return [NoteEvent(frequency: 1250, start: 0, duration: 0.05,
                              waveform: .triangle, volume: 0.25,
                              envelope: ADSREnvelope(attack: 0.002, decay: 0.02, sustain: 0.4, release: 0.02))]
        }
    }

    /// ~5 s ceremony jingle: I–V–vi–IV in C major, square lead + triangle bass.
    /// Chords: C, G, Am, F — one bar each at 120 BPM (0.5 s per beat, 2 beats per chord).
    public static var ceremonyJingle: [NoteEvent] {
        struct Chord {
            let root: Int     // MIDI for the bass
            let tones: [Int]  // chord tones for the lead arpeggio
        }
        let chords = [
            Chord(root: 36, tones: [60, 64, 67, 72]), // C
            Chord(root: 31, tones: [59, 62, 67, 74]), // G
            Chord(root: 33, tones: [57, 60, 64, 72]), // Am
            Chord(root: 29, tones: [57, 60, 65, 72]), // F
        ]
        let beat = 0.5
        var events: [NoteEvent] = []
        for (bar, chord) in chords.enumerated() {
            let barStart = Double(bar) * 2 * beat
            // Triangle bass: root half notes.
            for b in 0..<2 {
                events.append(NoteEvent(frequency: frequency(midi: chord.root),
                                        start: barStart + Double(b) * beat, duration: beat * 0.9,
                                        waveform: .triangle, volume: 0.55))
            }
            // Square lead: eighth-note arpeggio across the two beats.
            for e in 0..<4 {
                events.append(NoteEvent(frequency: frequency(midi: chord.tones[e]),
                                        start: barStart + Double(e) * beat / 2, duration: beat / 2 * 0.9,
                                        waveform: .square, volume: 0.3))
            }
        }
        // Final tonic, lead + bass together.
        let finale = 4 * 2 * beat
        events.append(NoteEvent(frequency: frequency(midi: 72), start: finale,
                                duration: beat * 1.8, waveform: .square, volume: 0.3,
                                envelope: ADSREnvelope(attack: 0.01, decay: 0.1, sustain: 0.7, release: 0.5)))
        events.append(NoteEvent(frequency: frequency(midi: 48), start: finale,
                                duration: beat * 1.8, waveform: .triangle, volume: 0.5,
                                envelope: ADSREnvelope(attack: 0.01, decay: 0.1, sustain: 0.7, release: 0.5)))
        return events
    }
}
