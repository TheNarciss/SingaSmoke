import Foundation

/// Opening hours in OpenStreetMap's `opening_hours` syntax, for the forms Singapore shops use:
/// "24/7", "Mo-Su 07:00-23:00", "Sa-Th 07:30-19:45; Fr 07:30-13:00", "Mo-Th, Su 09:00-17:00",
/// "Mo-Su 06:30-10:30, 12:00-14:30", "15:00-02:00" (past midnight), "Fr off".
/// Public holidays (PH) are ignored. Anything else makes the whole value unreadable (`nil`):
/// better to show the text as written than to guess.
public struct OpeningHours: Sendable, Hashable {
    /// A stretch of opening, in minutes since midnight. `end` past 1440 runs into the next day.
    public struct Span: Sendable, Hashable {
        public let start: Int
        public let end: Int
    }

    /// Index 0 is Monday, 6 is Sunday. An empty day is closed.
    public let week: [[Span]]
    /// The value as written in OpenStreetMap.
    public let text: String

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        self.text = trimmed
        if trimmed == "24/7" {
            week = Array(repeating: [Span(start: 0, end: 1440)], count: 7)
            return
        }
        var week = Array(repeating: [Span](), count: 7)
        var understood = false
        for rule in trimmed.components(separatedBy: ";") {
            let rule = rule.trimmingCharacters(in: .whitespaces)
            if rule.isEmpty { continue }
            guard let (days, spans) = Self.parse(rule: rule) else { return nil }
            for day in days { week[day] = spans }   // a later rule replaces an earlier one for its days
            understood = true
        }
        guard understood else { return nil }
        self.week = week
    }

    /// Open round the clock, every day.
    public var isAlwaysOpen: Bool {
        week.allSatisfy { day in day.contains { $0.start <= 0 && $0.end >= 1440 } }
    }

    // MARK: Status

    /// Whether the place is open at `date`, Singapore time, and until or from when.
    public func status(at date: Date, calendar: Calendar = .singapore) -> OpeningStatus {
        if isAlwaysOpen { return .alwaysOpen }
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let today = ((parts.weekday ?? 2) + 5) % 7   // Calendar: 1 = Sunday; here 0 = Monday
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)

        // Every opening from yesterday to a week ahead, in minutes from today's midnight, merged.
        var spans: [(start: Int, end: Int)] = []
        for offset in -1...7 {
            for span in week[(today + offset + 7) % 7] {
                spans.append((offset * 1440 + span.start, offset * 1440 + span.end))
            }
        }
        spans.sort { $0.start < $1.start }
        var merged: [(start: Int, end: Int)] = []
        for span in spans {
            if let last = merged.last, span.start <= last.end {
                merged[merged.count - 1].end = max(last.end, span.end)
            } else {
                merged.append(span)
            }
        }

        if let current = merged.first(where: { $0.start <= now && now < $0.end }) {
            return .open(minutesLeft: current.end - now, closing: current.end % 1440)
        }
        if let next = merged.first(where: { $0.start > now }) {
            let daysAhead = next.start / 1440
            return .closed(minutesUntil: next.start - now, opening: next.start % 1440,
                           daysAhead: daysAhead, weekday: (today + daysAhead) % 7)
        }
        return .closedAllWeek
    }

    // MARK: Schedule

    /// The week in a few lines, consecutive days with the same hours together:
    /// "Mon–Fri  10:30–22:30", "Sat–Sun  09:00–22:30", "Fri  closed".
    public var schedule: [(days: String, hours: String)] {
        if isAlwaysOpen { return [("Every day", "24 hours")] }
        var lines: [(String, String)] = []
        var first = 0
        while first < 7 {
            var last = first
            while last + 1 < 7 && week[last + 1] == week[first] { last += 1 }
            let days = first == last ? Self.dayNames[first]
                : first == 0 && last == 6 ? "Every day"
                : "\(Self.dayNames[first])–\(Self.dayNames[last])"
            let hours = week[first].isEmpty ? "Closed"
                : week[first].map { span in
                    span.start <= 0 && span.end >= 1440 ? "24 hours"
                        : "\(Format.time(span.start))–\(Format.time(span.end))"
                }.joined(separator: ", ")
            lines.append((days, hours))
            first = last + 1
        }
        return lines
    }

    public static let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    // MARK: Parsing

    private static let dayCodes = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    /// "Sa-Th 07:30-19:45" → (Saturday…Thursday, [07:30–19:45]). No days means every day.
    private static func parse(rule: String) -> (days: [Int], spans: [Span])? {
        var rest = Substring(rule)
        var days: [Int] = []
        var sawDays = false
        // Leading day selectors: "Mo-Fr", "Sa,Su", "Mo-Th, Su", "PH,Mo-Su".
        while let (selector, remainder) = leadingDaySelector(rest) {
            sawDays = true
            days += selector
            rest = remainder.drop { $0 == " " || $0 == "," }
        }
        if !sawDays { days = Array(0..<7) }
        let times = rest.trimmingCharacters(in: .whitespaces)
        if times == "off" || times == "closed" { return (Array(Set(days)).sorted(), []) }

        var spans: [Span] = []
        for piece in times.components(separatedBy: ",") {
            let piece = piece.trimmingCharacters(in: .whitespaces)
            guard let span = parseSpan(piece) else { return nil }
            spans.append(span)
        }
        guard !spans.isEmpty else { return nil }
        if sawDays && days.isEmpty { return ([], spans) }   // public holidays only: nothing to apply
        return (Array(Set(days)).sorted(), spans)
    }

    /// One day selector at the start of `text`: a day, a range of days (wrapping round the week),
    /// or PH (public holidays, returned as no day).
    private static func leadingDaySelector(_ text: Substring) -> ([Int], Substring)? {
        if text.hasPrefix("PH") || text.hasPrefix("SH") {
            return ([], text.dropFirst(2))
        }
        guard let from = dayIndex(text.prefix(2)) else { return nil }
        var rest = text.dropFirst(2)
        if rest.first == "-", let to = dayIndex(rest.dropFirst().prefix(2)) {
            rest = rest.dropFirst(3)
            var days: [Int] = []
            var day = from
            while true {
                days.append(day)
                if day == to { break }
                day = (day + 1) % 7
            }
            return (days, rest)
        }
        // A lone day must be followed by a separator, not by more letters ("Mon…" is not a code).
        if let next = rest.first, next.isLetter { return nil }
        return ([from], rest)
    }

    private static func dayIndex(_ code: Substring) -> Int? {
        dayCodes.firstIndex(of: String(code))
    }

    /// "07:00-23:00", "16:30 - 20:00", "05:30:00-17:00", "15:00-02:00", "00:00-24:00+".
    private static func parseSpan(_ text: String) -> Span? {
        let cleaned = text.replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "+"))
        let ends = cleaned.components(separatedBy: "-")
        guard ends.count == 2, let start = minutes(ends[0]), var end = minutes(ends[1]) else { return nil }
        if end <= start { end += 1440 }   // past midnight; "00:00-00:00" is the whole day
        return Span(start: start, end: end)
    }

    private static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count >= 2, parts.count <= 3,
              let hours = Int(parts[0]), let minutes = Int(parts[1]),
              (0...24).contains(hours), (0..<60).contains(minutes) else { return nil }
        return hours * 60 + minutes
    }
}

/// Open or closed, and until or from when.
public enum OpeningStatus: Sendable, Equatable {
    case alwaysOpen
    /// Open now; closes in `minutesLeft`, at `closing` (minute of the day).
    case open(minutesLeft: Int, closing: Int)
    /// Closed now; opens in `minutesUntil`, at `opening` (minute of the day), `daysAhead` days from
    /// today (0: later today), on `weekday` (0 = Monday).
    case closed(minutesUntil: Int, opening: Int, daysAhead: Int, weekday: Int)
    /// The hours list no opening at all.
    case closedAllWeek

    public var isOpen: Bool {
        switch self {
        case .alwaysOpen, .open: return true
        case .closed, .closedAllWeek: return false
        }
    }
}

public extension Calendar {
    /// Gregorian calendar on Singapore time: shop hours are local hours.
    static let singapore: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Singapore") ?? .current
        return calendar
    }()
}
