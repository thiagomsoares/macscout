import Foundation
@testable import MacscoutCore

enum AlertEngineTests {
    static func entry(_ sgv: Double, delta: Double? = nil, minutesAgo: Double = 2, from now: Date = Date()) -> GlucoseEntry {
        GlucoseEntry(id: UUID().uuidString,
                     date: now.addingTimeInterval(-minutesAgo * 60),
                     sgv: sgv, delta: delta, direction: .flat)
    }

    static func urgentLowFires() {
        let engine = AlertEngine()
        let now = Date()
        let events = engine.evaluate(entries: [entry(50, from: now)], settings: AlertSettings(), now: now)
        checkEqual(events.map(\.kind), [.urgentLow])
    }

    static func lowFiresBelowThreshold() {
        let engine = AlertEngine()
        let now = Date()
        let events = engine.evaluate(entries: [entry(65, from: now)], settings: AlertSettings(), now: now)
        checkEqual(events.map(\.kind), [.low])
    }

    static func highAndUrgentHigh() {
        let engine = AlertEngine()
        let now = Date()
        checkEqual(engine.evaluate(entries: [entry(190, from: now)], settings: AlertSettings(), now: now).map(\.kind), [.high])
        checkEqual(engine.evaluate(entries: [entry(260, from: now)], settings: AlertSettings(), now: now).map(\.kind), [.urgentHigh])
    }

    static func inRangeFiresNothing() {
        let engine = AlertEngine()
        let now = Date()
        check(engine.evaluate(entries: [entry(110, from: now)], settings: AlertSettings(), now: now).isEmpty)
    }

    static func cooldownSuppressesRepeats() {
        var settings = AlertSettings()
        settings.cooldownMinutes = 20
        let engine = AlertEngine()
        let t0 = Date()
        checkEqual(engine.evaluate(entries: [entry(65, from: t0)], settings: settings, now: t0).count, 1)
        let t1 = t0.addingTimeInterval(5 * 60)
        check(engine.evaluate(entries: [entry(64, from: t1)], settings: settings, now: t1).isEmpty,
              "repeat within cooldown should be suppressed")
        let t2 = t0.addingTimeInterval(21 * 60)
        checkEqual(engine.evaluate(entries: [entry(63, from: t2)], settings: settings, now: t2).map(\.kind), [.low])
    }

    static func urgentCooldownIsShorter() {
        var settings = AlertSettings()
        settings.cooldownMinutes = 20
        settings.urgentCooldownMinutes = 10
        let engine = AlertEngine()
        let t0 = Date()
        checkEqual(engine.evaluate(entries: [entry(50, from: t0)], settings: settings, now: t0).map(\.kind), [.urgentLow])
        let t1 = t0.addingTimeInterval(11 * 60)
        checkEqual(engine.evaluate(entries: [entry(49, from: t1)], settings: settings, now: t1).map(\.kind), [.urgentLow])
    }

    static func crossingBackIntoRangeResetsKind() {
        var settings = AlertSettings()
        settings.cooldownMinutes = 60
        let engine = AlertEngine()
        let t0 = Date()
        _ = engine.evaluate(entries: [entry(65, from: t0)], settings: settings, now: t0)
        let t1 = t0.addingTimeInterval(2 * 60)
        _ = engine.evaluate(entries: [entry(100, from: t1)], settings: settings, now: t1)
        let t2 = t0.addingTimeInterval(4 * 60)
        checkEqual(engine.evaluate(entries: [entry(66, from: t2)], settings: settings, now: t2).map(\.kind), [.low],
                   "low should re-fire after crossing back into range")
    }

    static func deltaAlerts() {
        var settings = AlertSettings()
        settings.risingFastEnabled = true
        settings.fallingFastEnabled = true
        let engine = AlertEngine()
        let now = Date()
        checkEqual(engine.evaluate(entries: [entry(120, delta: 6, from: now)], settings: settings, now: now).map(\.kind), [.risingFast])
        checkEqual(engine.evaluate(entries: [entry(118, delta: -6, from: now)], settings: settings, now: now).map(\.kind), [.fallingFast])
        let engine2 = AlertEngine()
        check(engine2.evaluate(entries: [entry(120, delta: 9, from: now)], settings: AlertSettings(), now: now).isEmpty,
              "delta alerts are disabled by default")
    }

    static func staleData() {
        let engine = AlertEngine()
        let now = Date()
        checkEqual(engine.evaluate(entries: [entry(110, minutesAgo: 15, from: now)], settings: AlertSettings(), now: now).map(\.kind), [.staleData])
        check(engine.evaluate(entries: [entry(110, minutesAgo: 3, from: now)], settings: AlertSettings(), now: now).isEmpty)
    }

    static func disabledCategoriesNeverFire() {
        var settings = AlertSettings()
        settings.urgentLowEnabled = false
        settings.lowEnabled = false
        settings.staleDataEnabled = false
        let engine = AlertEngine()
        let now = Date()
        check(engine.evaluate(entries: [entry(40, minutesAgo: 99, from: now)], settings: settings, now: now).isEmpty)
    }

    static func quietHoursCrossingMidnight() {
        let q = QuietHours(enabled: true, fromMinutes: 22 * 60, toMinutes: 7 * 60)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        func at(_ h: Int, _ m: Int = 0) -> Date {
            cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: h, minute: m))!
        }
        check(q.contains(at(23), calendar: cal))
        check(q.contains(at(0), calendar: cal))
        check(q.contains(at(6, 59), calendar: cal))
        check(!q.contains(at(7), calendar: cal))
        check(!q.contains(at(12), calendar: cal))
        check(!q.contains(at(21, 59), calendar: cal))
    }

    static func quietHoursSameDayAndDisabled() {
        let q = QuietHours(enabled: true, fromMinutes: 12 * 60, toMinutes: 13 * 60)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let noon = cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 12, minute: 30))!
        let evening = cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 20))!
        check(q.contains(noon, calendar: cal))
        check(!q.contains(evening, calendar: cal))
        check(!QuietHours(enabled: false).contains(noon, calendar: cal))
    }

    static func defaultSounds() {
        // Synthesized 8-bit cues are the default for every category.
        let s = AlertSettings()
        for kind in AlertKind.allCases {
            checkEqual(s.sound(for: kind), .chiptune, "default sound for \(kind)")
        }
    }

    static var tests: [(String, TestBody)] {
        [("urgentLowFires", urgentLowFires),
         ("lowFiresBelowThreshold", lowFiresBelowThreshold),
         ("highAndUrgentHigh", highAndUrgentHigh),
         ("inRangeFiresNothing", inRangeFiresNothing),
         ("cooldownSuppressesRepeats", cooldownSuppressesRepeats),
         ("urgentCooldownIsShorter", urgentCooldownIsShorter),
         ("crossingBackIntoRangeResetsKind", crossingBackIntoRangeResetsKind),
         ("deltaAlerts", deltaAlerts),
         ("staleData", staleData),
         ("disabledCategoriesNeverFire", disabledCategoriesNeverFire),
         ("quietHoursCrossingMidnight", quietHoursCrossingMidnight),
         ("quietHoursSameDayAndDisabled", quietHoursSameDayAndDisabled),
         ("defaultSounds", defaultSounds)]
    }
}
