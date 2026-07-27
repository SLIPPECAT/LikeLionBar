import Foundation

/// 지금 띄워야 할 알림.
public enum Reminder: Equatable, Sendable {
    /// `attempt`는 1부터. `isFinal`이면 마지막 경고다.
    case checkIn(attempt: Int, isFinal: Bool)
    case classroom
    case camera
    case checkOut(attempt: Int)
}

/// 두 시각 사이에 지나간 알림 시점을 찾아낸다.
///
/// 앱이 항상 떠 있으므로 미리 예약하는 대신 매 틱마다 "방금 지나쳤나"를 묻는다.
/// 주말·쉬는 날·이미 완료한 단계를 그때그때 반영할 수 있어 예약 취소 로직이 필요 없다.
public struct ReminderEngine: Sendable {
    public var schedule: Schedule
    public var calendar: Calendar

    public init(schedule: Schedule = .default, calendar: Calendar = .current) {
        self.schedule = schedule
        self.calendar = calendar
    }

    /// `from` 이후 `to` 이하 구간에 걸린 알림들.
    public func due(from: Date, to: Date, state: DayState) -> [Reminder] {
        guard from < to else { return [] }
        guard !isRestDay(to, state: state) else { return [] }

        var due: [Reminder] = []

        if !state.isDone(.checkIn) {
            let last = schedule.checkInReminders.count - 1
            for (index, time) in schedule.checkInReminders.enumerated()
            where crossed(time, from: from, to: to) {
                due.append(.checkIn(attempt: index + 1, isFinal: index == last))
            }
        }

        // 입실을 안 했으면 강의실을 조를 차례가 아니다.
        if state.isDone(.checkIn), !state.isDone(.classroom),
           crossed(schedule.classroomReminder, from: from, to: to) {
            due.append(.classroom)
        }

        if !state.isDone(.checkOut) {
            for (index, time) in schedule.checkOutReminders.enumerated()
            where crossed(time, from: from, to: to) {
                due.append(.checkOut(attempt: index + 1))
            }
        }

        // 카메라는 완료 개념이 없다. 수업 중이면 계속 확인시킨다.
        for time in schedule.cameraReminderTimes where crossed(time, from: from, to: to) {
            due.append(.camera)
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
    public var step: Step {
        switch self {
        case .checkIn:   return .checkIn
        case .classroom: return .classroom
        case .camera:    return .camera
        case .checkOut:  return .checkOut
        }
    }

    public var title: String {
        switch self {
        case .checkIn(_, let isFinal): return isFinal ? "지금 안 하면 지각입니다" : "QR 입실"
        case .classroom:               return "강의실 입장"
        case .camera:                  return "카메라 확인"
        case .checkOut:                return "QR 퇴실"
        }
    }

    public var body: String {
        switch self {
        case .checkIn(_, let isFinal):
            return isFinal
                ? "마감이 코앞입니다. 고용24 인증부터 바로 시작하세요."
                : "고용24 인증 후 QR 입퇴실을 처리하세요."
        case .classroom:
            return "원격 강의실에 입장하세요. 휴대폰 인증이 필요합니다."
        case .camera:
            return "쉬는시간이 아니면 카메라를 켜 두세요."
        case .checkOut:
            return "QR 입퇴실로 퇴실 처리하세요. 놓치면 오늘 출석이 인정되지 않습니다."
        }
    }

    /// 시스템 알림 소리를 줄지. 카메라는 자주 울려서 조용히 띄운다.
    public var isNoisy: Bool {
        if case .camera = self { return false }
        return true
    }
}
