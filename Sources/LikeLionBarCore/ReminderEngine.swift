import Foundation

/// 지금 띄워야 할 알림.
public enum Reminder: Equatable, Sendable {
    /// `attempt`는 1부터. `isFinal`이면 마지막 경고다.
    case checkIn(attempt: Int, isFinal: Bool)
    case classroom(isFinal: Bool)
    /// 매시간 사진. `hour`는 대상 시간대.
    case photo(hour: Int, isFinal: Bool)
    case checkOut(attempt: Int)
    /// 사용자가 직접 등록한 알림.
    case custom(title: String)
}

/// 두 시각 사이에 지나간 알림 시점을 찾아낸다.
///
/// 앱이 항상 떠 있으므로 미리 예약하는 대신 매 틱마다 "방금 지나쳤나"를 묻는다.
/// 주말·쉬는 날·이미 완료한 단계를 그때그때 반영할 수 있어 예약 취소 로직이 필요 없다.
public struct ReminderEngine: Sendable {
    public var schedule: Schedule
    /// 사용자가 등록한 알림들. 출결과 무관하게 따로 판단한다.
    public var custom: [CustomReminder]
    public var calendar: Calendar

    public init(
        schedule: Schedule = .default,
        custom: [CustomReminder] = [],
        calendar: Calendar = .current
    ) {
        self.schedule = schedule
        self.custom = custom
        self.calendar = calendar
    }

    /// `from` 이후 `to` 이하 구간에 걸린 알림들.
    public func due(from: Date, to: Date, state: DayState) -> [Reminder] {
        guard from < to else { return [] }

        // 커스텀 알림은 쉬는 날에도 울려야 한다. 병원 예약을 쉬는 날이라고 거를 순 없다.
        var due: [Reminder] = custom
            .filter { $0.applies(to: to, isDayOff: state.isDayOff, calendar: calendar) }
            .filter { crossed($0.time, from: from, to: to) }
            .map { .custom(title: $0.title) }

        guard !isRestDay(to, state: state) else { return due }

        if !state.isDone(.checkIn) {
            let last = schedule.checkInReminders.count - 1
            for (index, time) in schedule.checkInReminders.enumerated()
            where crossed(time, from: from, to: to) {
                due.append(.checkIn(attempt: index + 1, isFinal: index == last))
            }
        }

        // 입실을 안 했으면 강의실을 조를 차례가 아니다.
        if state.isDone(.checkIn), !state.isDone(.classroom) {
            let last = schedule.classroomReminders.count - 1
            for (index, time) in schedule.classroomReminders.enumerated()
            where crossed(time, from: from, to: to) {
                due.append(.classroom(isFinal: index == last))
            }
        }

        if !state.isDone(.checkOut) {
            for (index, time) in schedule.checkOutReminders.enumerated()
            where crossed(time, from: from, to: to) {
                due.append(.checkOut(attempt: index + 1))
            }
        }

        // 사진은 매시간 마감이 따로 있다. 이번 시간에 안 찍었으면 조른다.
        let hour = calendar.component(.hour, from: to)
        if schedule.photoHours.contains(hour), !state.isPhotoDone(hour: hour) {
            let last = schedule.photoReminderMinutes.count - 1
            for (index, minute) in schedule.photoReminderMinutes.enumerated()
            where crossed(HM(hour, minute), from: from, to: to) {
                due.append(.photo(hour: hour, isFinal: index == last))
            }
        }

        return due
    }

    // MARK: - 도우미

    private func crossed(_ time: HM, from: Date, to: Date) -> Bool {
        guard let moment = calendar.date(
            bySettingHour: time.hour, minute: time.minute, second: 0, of: to
        ) else { return false }
        return moment > from && moment <= to
    }

    private func isRestDay(_ date: Date, state: DayState) -> Bool {
        if state.isDayOff { return true }
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }
}

// MARK: - 문구

extension Reminder {
    /// 출결 단계. 커스텀 알림은 완료 개념이 없어 nil이다.
    public var step: Step? {
        switch self {
        case .checkIn:   return .checkIn
        case .classroom: return .classroom
        case .photo:     return .camera
        case .checkOut:  return .checkOut
        case .custom:    return nil
        }
    }

    public var title: String {
        switch self {
        case .checkIn(_, let isFinal): return isFinal ? "지금 안 하면 지각입니다" : "QR 입실"
        case .classroom(let isFinal):  return isFinal ? "강의실 입장 (마지막 안내)" : "강의실 입장"
        case .photo(let hour, _):      return "\(hour)시 사진"
        case .checkOut:                return "QR 퇴실"
        case .custom(let title):       return title
        }
    }

    public func body(deadlineMinute: Int) -> String {
        switch self {
        case .checkIn(_, let isFinal):
            return isFinal
                ? "마감이 코앞입니다. 고용24 인증부터 바로 시작하세요."
                : "고용24 인증 후 QR 입퇴실을 처리하세요."
        case .classroom:
            return "원격 강의실에 입장하세요. 휴대폰 인증이 필요합니다."
        case .photo(let hour, let isFinal):
            let deadline = String(format: "%d시 %02d분", hour, deadlineMinute)
            return isFinal
                ? "\(deadline)까지 얼마 안 남았습니다. 지금 찍으세요."
                : "\(deadline)까지 카메라로 사진을 찍으세요."
        case .checkOut:
            return "QR 입퇴실로 퇴실 처리하세요. 놓치면 오늘 출석이 인정되지 않습니다."
        case .custom:
            return "직접 등록한 알림입니다."
        }
    }
}
