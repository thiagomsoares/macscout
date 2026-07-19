import Foundation

/// A fired alert.
public struct AlertEvent: Equatable, Sendable {
    public let kind: AlertKind
    /// Triggering value in mg/dL (glucose or delta; minutes for stale data).
    public let value: Double
    public let message: String

    public init(kind: AlertKind, value: Double, message: String) {
        self.kind = kind
        self.value = value
        self.message = message
    }
}

/// Evaluates glucose entries against alert thresholds with cooldown-based dedup.
///
/// For each category the engine tracks the last fired date; a repeat is
/// suppressed until `cooldownMinutes` (or `urgentCooldownMinutes` for urgent
/// kinds) has elapsed. When the condition clears (value crosses back into
/// range, or fresh data arrives) the category resets so it can fire again
/// immediately on the next crossing.
public final class AlertEngine {
    private var lastFired: [AlertKind: Date] = [:]
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Forget all firing history (e.g. after settings change or reconnect).
    public func reset() { lastFired.removeAll() }

    /// Evaluate the newest entry against settings. `entries` should be newest-first.
    /// Returns events that should fire now (already cooldown-filtered).
    @discardableResult
    public func evaluate(entries: [GlucoseEntry], settings: AlertSettings, now: Date = Date()) -> [AlertEvent] {
        guard let latest = entries.first else { return [] }
        var events: [AlertEvent] = []
        let sgv = latest.sgv

        // Threshold crossings, most urgent first. Only the single most severe
        // matching low/high category fires per evaluation.
        if settings.urgentLowEnabled, sgv <= settings.urgentLowThreshold {
            fire(.urgentLow, value: sgv, settings: settings, now: now,
                 message: "Urgent low: \(Int(sgv.rounded())) mg/dL", into: &events)
        } else if settings.lowEnabled, sgv < settings.lowThreshold {
            fire(.low, value: sgv, settings: settings, now: now,
                 message: "Low: \(Int(sgv.rounded())) mg/dL", into: &events)
        } else if settings.urgentHighEnabled, sgv >= settings.urgentHighThreshold {
            fire(.urgentHigh, value: sgv, settings: settings, now: now,
                 message: "Urgent high: \(Int(sgv.rounded())) mg/dL", into: &events)
        } else if settings.highEnabled, sgv > settings.highThreshold {
            fire(.high, value: sgv, settings: settings, now: now,
                 message: "High: \(Int(sgv.rounded())) mg/dL", into: &events)
        } else {
            // Back in range: clear all glucose categories so they re-arm.
            clearKind(.urgentLow)
            clearKind(.low)
            clearKind(.high)
            clearKind(.urgentHigh)
        }

        // Rate-of-change alerts use the reading's delta.
        if let delta = latest.delta {
            if settings.risingFastEnabled, delta >= settings.risingFastDelta {
                fire(.risingFast, value: delta, settings: settings, now: now,
                     message: "Rising fast: +\(Int(delta.rounded())) mg/dL", into: &events)
            } else {
                clearKind(.risingFast)
            }
            if settings.fallingFastEnabled, delta <= settings.fallingFastDelta {
                fire(.fallingFast, value: delta, settings: settings, now: now,
                     message: "Falling fast: \(Int(delta.rounded())) mg/dL", into: &events)
            } else {
                clearKind(.fallingFast)
            }
        }

        // Stale data.
        let ageMinutes = now.timeIntervalSince(latest.date) / 60
        if settings.staleDataEnabled, ageMinutes >= Double(settings.staleMinutes) {
            fire(.staleData, value: ageMinutes, settings: settings, now: now,
                 message: "No new data for \(Int(ageMinutes)) min", into: &events)
        } else {
            clearKind(.staleData)
        }

        return events
    }

    /// Record a fired alert if past its cooldown; appends the event when it fires.
    private func fire(_ kind: AlertKind, value: Double, settings: AlertSettings,
                      now: Date, message: String, into events: inout [AlertEvent]) {
        if let last = lastFired[kind] {
            let cooldown = kind.isUrgent ? settings.urgentCooldownMinutes : settings.cooldownMinutes
            if now.timeIntervalSince(last) < Double(cooldown) * 60 {
                return
            }
        }
        lastFired[kind] = now
        events.append(AlertEvent(kind: kind, value: value, message: message))
    }

    private func clearKind(_ kind: AlertKind) {
        lastFired.removeValue(forKey: kind)
    }

    /// True when `now` falls inside configured quiet hours (sounds muted only).
    public func inQuietHours(settings: AlertSettings, now: Date = Date()) -> Bool {
        settings.quietHours.contains(now, calendar: calendar)
    }
}
