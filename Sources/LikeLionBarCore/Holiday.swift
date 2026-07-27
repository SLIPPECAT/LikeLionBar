import Foundation

/// 공휴일 하나.
public struct Holiday: Codable, Equatable, Sendable {
    /// `"2026-02-16"` 형식.
    public let date: String
    public let name: String

    public init(date: String, name: String) {
        self.date = date
        self.name = name
    }

    public static func key(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// 연도별 공휴일 캐시.
///
/// 부트캠프가 공휴일에 수업할 수도 있고, 반대로 공휴일이 아닌 자체 휴일도 있다.
/// 그래서 이건 확정이 아니라 **제안**이고, 사용자가 언제든 되돌릴 수 있어야 한다.
public struct HolidayCalendar: Codable, Equatable, Sendable {
    public var year: Int
    public var holidays: [Holiday]
    public var fetchedAt: Date

    public init(year: Int, holidays: [Holiday], fetchedAt: Date = Date()) {
        self.year = year
        self.holidays = holidays
        self.fetchedAt = fetchedAt
    }

    public func holiday(on date: Date, calendar: Calendar) -> Holiday? {
        let key = Holiday.key(for: date, calendar: calendar)
        return holidays.first { $0.date == key }
    }

    /// 이 캐시가 해당 날짜를 판단할 수 있는지.
    public func covers(_ date: Date, calendar: Calendar) -> Bool {
        calendar.component(.year, from: date) == year
    }
}
