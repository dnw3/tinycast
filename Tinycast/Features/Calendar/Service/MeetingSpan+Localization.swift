import Foundation

extension MeetingSpan {
    var readEventsDescription: String {
        switch self {
        case .today:
            String(localized: "Reads today's events for join links. Nothing leaves this Mac.")
        case .todayAndTomorrow:
            String(localized: "Reads today's and tomorrow's events for join links. Nothing leaves this Mac.")
        case .nextSevenDays:
            String(localized: "Reads the next 7 days' events for join links. Nothing leaves this Mac.")
        }
    }

    var emptyScheduleDescription: String {
        switch self {
        case .today: String(localized: "Nothing scheduled today")
        case .todayAndTomorrow: String(localized: "Nothing scheduled today or tomorrow")
        case .nextSevenDays: String(localized: "Nothing scheduled in the next 7 days")
        }
    }
}
