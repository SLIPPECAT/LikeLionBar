import Foundation

/// 현재 시각과 오늘 상태로부터 메뉴바 표시를 결정한다.
///
/// AppKit에 의존하지 않고 `now`를 인자로 받으므로, 다음날 아침을 기다리지 않고
/// 임의 시각을 주입해 모든 상태 전이를 테스트할 수 있다.
public struct ScheduleEngine: Sendable {
    public var schedule: Schedule
    public var calendar: Calendar

    public init(schedule: Schedule = .default, calendar: Calendar = .current) {
        self.schedule = schedule
        self.calendar = calendar
    }

    public func presentation(now: Date, state: DayState) -> BarPresentation {
        // 주말이거나 쉬는 날로 표시했으면 아무것도 조르지 않는다.
        guard !isRestDay(now: now, state: state) else { return quiet(state) }

        let windowStart = time(schedule.checkInWindowStart, on: now)
        let deadline = time(schedule.lateDeadline, on: now)
        let classEnd = time(schedule.classEnd, on: now)
        let checkOutFrom = time(schedule.checkOutRemindFrom, on: now)

        // 1. 입실 미완료가 최우선. 지각은 되돌릴 수 없는 손해라 다른 무엇보다 앞선다.
        if !state.isDone(.checkIn), now >= windowStart, now < classEnd {
            let remaining = deadline.timeIntervalSince(now)
            if remaining > 0 {
                // 여유가 있을 땐 무표정, 마감이 다가오면 화난 얼굴로 넘어간다.
                let urgent = remaining <= schedule.urgentThreshold
                return BarPresentation(
                    face: urgent ? .angry : .neutral,
                    text: Self.countdown(remaining),
                    tone: .alert,
                    blinking: urgent
                )
            }
            // 마감을 넘겼어도 출석 자체는 받아야 하므로 계속 보여준다.
            // 다만 이제 서두를 이유가 없으니 깜빡이지는 않는다.
            return BarPresentation(face: .crying, text: "지각", tone: .alert)
        }

        // 2. 퇴실. 놓치면 그날 출석이 통째로 날아가므로 하루 끝까지 표시한다.
        if !state.isDone(.checkOut), now >= checkOutFrom {
            return BarPresentation(face: .angry, text: "퇴실", tone: .warning)
        }

        // 3. 강의실 입장. 버튼이 실제로 활성화되는 시각부터 조른다.
        if state.isDone(.checkIn), !state.isDone(.classroom),
           now >= time(schedule.classroomAvailableFrom, on: now), now < classEnd {
            return BarPresentation(face: .angry, text: "강의실", tone: .warning)
        }

        // 4. 이번 시간 사진. 매시 마감이 따로 있어 시간마다 되풀이된다.
        //    첫 알림 때부터 띄우면 하루 종일 시끄러우므로 마지막 알림 이후에만 보여준다.
        if let photo = photoPresentation(now: now, state: state) {
            return photo
        }

        return quiet(state)
    }

    /// 이번 시간 사진이 남았을 때의 카운트다운. 아직 조를 때가 아니면 nil.
    private func photoPresentation(now: Date, state: DayState) -> BarPresentation? {
        let hour = calendar.component(.hour, from: now)
        guard schedule.photoHours.contains(hour), !state.isPhotoDone(hour: hour) else {
            return nil
        }
        guard let lastReminder = schedule.photoReminderMinutes.max() else { return nil }

        let showFrom = time(HM(hour, lastReminder), on: now)
        let deadline = time(HM(hour, schedule.photoDeadlineMinute), on: now)
        guard now >= showFrom, now < deadline else { return nil }

        let remaining = deadline.timeIntervalSince(now)
        return BarPresentation(
            face: .angry,
            // 입실 카운트다운과 구분되어야 무엇이 급한지 헷갈리지 않는다.
            // 이모지는 컬러라 상태색이 안 먹고 메뉴바 크기에서 뭉개진다.
            text: "사진 " + Self.countdown(remaining),
            tone: .alert,
            blinking: remaining <= schedule.photoUrgentThreshold
        )
    }

    /// 조를 것이 없는 상태. 오늘 뭔가 했으면 웃고, 아니면 무표정.
    private func quiet(_ state: DayState) -> BarPresentation {
        state.hasAnyProgress
            ? BarPresentation(face: .happy, tone: .done)
            : BarPresentation(face: .neutral, tone: .quiet)
    }

    private func isRestDay(now: Date, state: DayState) -> Bool {
        if state.isDayOff { return true }
        let weekday = calendar.component(.weekday, from: now)
        // Gregorian 기준 1 = 일요일, 7 = 토요일
        return weekday == 1 || weekday == 7
    }

    /// `reference`와 같은 날짜의 `hm` 시각.
    private func time(_ hm: HM, on reference: Date) -> Date {
        calendar.date(bySettingHour: hm.hour, minute: hm.minute, second: 0, of: reference)
            ?? reference
    }

    /// 남은 시간을 `MM:SS`로. 초 단위가 줄어드는 게 보여야 다급함이 전달된다.
    public static func countdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
