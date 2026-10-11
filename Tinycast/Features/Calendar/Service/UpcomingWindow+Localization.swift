import Foundation

extension UpcomingWindow {
    static func countdown(to start: Date, now: Date) -> String {
        let delta = start.timeIntervalSince(now)
        if delta > 0 { return String(localized: "in \(duration(delta, rounding: .up))") }
        return String(localized: "Now")
    }

    static func rowPill(for event: MeetingEvent, now: Date, calendar: Calendar) -> RowPill? {
        if event.isInProgress(now: now) { return RowPill(text: String(localized: "Now"), isImminent: true) }
        let delta = event.start.timeIntervalSince(now)
        guard delta > 0 else { return nil }
        let isImminent = delta <= 60 * 60
        guard isImminent || calendar.isDate(event.start, inSameDayAs: now) else {
            return RowPill(text: dayLabel(event.start, calendar: calendar), isImminent: false)
        }
        return RowPill(text: countdown(to: event.start, now: now), isImminent: isImminent)
    }

    static func dayLabel(_ date: Date, calendar: Calendar) -> String {
        date.formatted(calendar.formatStyle.weekday(.abbreviated).month(.abbreviated).day())
    }

    static func menuBarCountdown(for event: MeetingEvent, now: Date) -> String {
        if now < event.start { return countdown(to: event.start, now: now) }
        if now < event.start.addingTimeInterval(5 * 60) { return String(localized: "Now") }
        if now < event.end { return String(localized: "\(duration(event.end.timeIntervalSince(now), rounding: .down)) left") }
        return String(localized: "Now")
    }

    private static func duration(
        _ interval: TimeInterval, rounding: FloatingPointRoundingRule
    ) -> String {
        let minutes = max(1, Int((interval / 60).rounded(rounding)))
        guard minutes > 60 else { return String(localized: "\(minutes) min") }
        let hours = max(1, Int((Double(minutes) / 60).rounded()))
        return String(localized: "\(hours) hr")
    }
}
