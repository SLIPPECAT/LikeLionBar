import Foundation

/// 사용자가 직접 등록한 알림. "1시 40분 병원", "3시 10분 나가야 함" 같은 것.
///
/// 출결 단계와 달리 완료 개념이 없다. 그 시각에 한 번 알려주는 게 전부다.
public struct CustomReminder: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var time: HM
    public var title: String
    /// true면 매 평일 반복, false면 `day` 하루만.
    public var isDaily: Bool
    /// 일회성일 때 대상 날짜. 그날이 지나면 정리된다.
    public var day: DateComponents?
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        time: HM,
        title: String,
        isDaily: Bool = false,
        day: DateComponents? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.time = time
        self.title = title
        self.isDaily = isDaily
        self.day = day
        self.isEnabled = isEnabled
    }

    /// 이 날짜에 울려야 하는지.
    ///
    /// 일회성은 쉬는 날이든 주말이든 그날이면 울린다 — 병원 예약을 쉬는 날이라고
    /// 건너뛰면 곤란하다. 반복은 평일에만, 쉬는 날로 표시했으면 쉰다.
    public func applies(to date: Date, isDayOff: Bool, calendar: Calendar) -> Bool {
        guard isEnabled else { return false }

        if isDaily {
            guard !isDayOff else { return false }
            let weekday = calendar.component(.weekday, from: date)
            return weekday != 1 && weekday != 7
        }

        guard let day else { return false }
        let today = calendar.dateComponents([.year, .month, .day], from: date)
        return day.year == today.year && day.month == today.month && day.day == today.day
    }

    /// 일회성인데 날짜가 지났으면 더 쓸모가 없다.
    public func isExpired(on date: Date, calendar: Calendar) -> Bool {
        guard !isDaily, let day else { return false }
        guard let dayStart = calendar.date(from: day) else { return true }
        return calendar.startOfDay(for: date) > calendar.startOfDay(for: dayStart)
    }

    /// 오늘 하루짜리로 새로 만든다.
    public static func today(time: HM, title: String, on date: Date, calendar: Calendar) -> CustomReminder {
        CustomReminder(
            time: time,
            title: title,
            isDaily: false,
            day: calendar.dateComponents([.year, .month, .day], from: date)
        )
    }
}
