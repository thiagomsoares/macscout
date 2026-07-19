import Foundation
@testable import MacscoutCore

enum ChiptuneTests {
    static func wavHeaderIsValid() {
        let pcm: [Int16] = [0, 1000, -1000, 2000]
        let wav = Chiptune.wavData(pcm: pcm)
        checkEqual(wav.count, 44 + pcm.count * 2)
        checkEqual(String(decoding: wav[0..<4], as: UTF8.self), "RIFF")
        checkEqual(String(decoding: wav[8..<12], as: UTF8.self), "WAVE")
        checkEqual(String(decoding: wav[12..<16], as: UTF8.self), "fmt ")
        checkEqual(String(decoding: wav[36..<40], as: UTF8.self), "data")
        // RIFF chunk size = 36 + data size; data size = samples × 2.
        checkEqual(wav[4..<8].withUnsafeBytes { $0.load(as: UInt32.self) }, 36 + UInt32(pcm.count * 2))
        checkEqual(wav[40..<44].withUnsafeBytes { $0.load(as: UInt32.self) }, UInt32(pcm.count * 2))
        // Sample rate at offset 24.
        checkEqual(wav[24..<28].withUnsafeBytes { $0.load(as: UInt32.self) }, UInt32(Chiptune.sampleRate))
        // PCM payload round-trips little-endian.
        checkEqual(wav[44..<46].withUnsafeBytes { $0.load(as: UInt16.self) }, 0)
        checkEqual(Int16(bitPattern: wav[46..<48].withUnsafeBytes { $0.load(as: UInt16.self) }), 1000)
    }

    static func renderLengthMatchesDuration() {
        let events = [NoteEvent(frequency: 440, start: 0, duration: 0.5, waveform: .square)]
        let pcm = Chiptune.renderPCM(events: events)
        // ~0.5 s at 44.1 kHz (plus one sample).
        check(abs(Double(pcm.count) - 0.5 * 44100) <= 2, "unexpected length \(pcm.count)")
    }

    static func squareWaveform() {
        checkEqual(Chiptune.oscillator(.square, at: 0.1 / 440, frequency: 440), 1)
        checkEqual(Chiptune.oscillator(.square, at: 0.6 / 440, frequency: 440), -1)
    }

    static func triangleWaveform() {
        checkClose(Chiptune.oscillator(.triangle, at: 0.0, frequency: 440), -1)
        checkClose(Chiptune.oscillator(.triangle, at: 0.25 / 440, frequency: 440), 0)
        checkClose(Chiptune.oscillator(.triangle, at: 0.5 / 440, frequency: 440), 1)
        checkClose(Chiptune.oscillator(.triangle, at: 0.75 / 440, frequency: 440), 0)
    }

    static func envelopeShape() {
        let env = ADSREnvelope(attack: 0.1, decay: 0.1, sustain: 0.5, release: 0.1)
        checkClose(env.gain(at: 0.05, duration: 1), 0.5)          // attack ramp
        checkClose(env.gain(at: 0.2, duration: 1), 0.5)           // decay → sustain
        checkClose(env.gain(at: 0.5, duration: 1), 0.5)           // sustain
        check(env.gain(at: 0.995, duration: 1) < 0.05, "release should fade out")
        checkClose(env.gain(at: 0, duration: 1), 0)
    }

    static func noClippingWhenNormalized() {
        // Many loud overlapping notes must normalize instead of overflowing.
        let events = (0..<8).map { NoteEvent(frequency: 220 + Double($0) * 110, start: 0,
                                             duration: 0.1, waveform: .square, volume: 1) }
        let pcm = Chiptune.renderPCM(events: events)
        check(pcm.allSatisfy { $0 >= Int16.min && $0 <= Int16.max })
        check(pcm.contains { abs($0) > 30000 }, "expected a near-full-scale peak after normalization")
    }

    static func cueTableShape() {
        let urgentLow = Chiptune.cue(for: .urgentLow)
        checkEqual(urgentLow.count, 3)
        check(urgentLow[0].frequency > urgentLow[1].frequency && urgentLow[1].frequency > urgentLow[2].frequency,
              "urgent low must descend")
        let urgentHigh = Chiptune.cue(for: .urgentHigh)
        checkEqual(urgentHigh.count, 3)
        check(urgentHigh[0].frequency < urgentHigh[1].frequency && urgentHigh[1].frequency < urgentHigh[2].frequency,
              "urgent high must ascend")
        let low = Chiptune.cue(for: .low)
        checkEqual(low.count, 2)
        check(low.allSatisfy { $0.waveform == .square })
        let high = Chiptune.cue(for: .high)
        checkEqual(high.count, 2)
        check(high.allSatisfy { $0.waveform == .triangle })
        check(high[1].frequency > high[0].frequency, "high blips must rise")
        checkEqual(Chiptune.cue(for: .staleData).count, 1)
    }

    static func ceremonyJingleDurationAndVoices() {
        let jingle = Chiptune.ceremonyJingle
        let end = jingle.map { $0.start + $0.duration }.max() ?? 0
        check(end >= 4.5 && end <= 6.0, "jingle should be ~5 s, is \(end)")
        check(jingle.contains { $0.waveform == .square }, "needs square lead")
        check(jingle.contains { $0.waveform == .triangle }, "needs triangle bass")
        // Rendering the full jingle must succeed and stay in range.
        let pcm = Chiptune.renderPCM(events: jingle)
        check(abs(Double(pcm.count) - end * 44100) <= 2, "unexpected jingle length \(pcm.count)")
    }

    static var tests: [(String, TestBody)] {
        [("wavHeaderIsValid", wavHeaderIsValid),
         ("renderLengthMatchesDuration", renderLengthMatchesDuration),
         ("squareWaveform", squareWaveform),
         ("triangleWaveform", triangleWaveform),
         ("envelopeShape", envelopeShape),
         ("noClippingWhenNormalized", noClippingWhenNormalized),
         ("cueTableShape", cueTableShape),
         ("ceremonyJingleDurationAndVoices", ceremonyJingleDurationAndVoices)]
    }
}
