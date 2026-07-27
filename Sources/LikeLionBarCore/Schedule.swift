import Foundation

/// 하루 중의 시각 (시:분).
public struct HM: Equatable, Codable, Comparable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(_ hour: Int, _ minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    /// 자정부터 흐른 분.
    public var minutesSinceMidnight: Int { hour * 60 + minute }

    public init(minutesSinceMidnight m: Int) {
        self.init(m / 60, m % 60)
    }

    public static func < (lhs: HM, rhs: HM) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    /// `"08:47"` 형태. 설정 창에서 사람이 직접 입력·확인하는 표현이다.
    public var text: String { String(format: "%02d:%02d", hour, minute) }

    public init?(text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m)
        else { return nil }
        self.init(h, m)
    }

    /// `"08:47, 08:56"` → `[HM]`. 잘못 입력한 항목은 조용히 버린다.
    public static func list(from text: String) -> [HM] {
        text.split(separator: ",").compactMap { HM(text: String($0)) }
    }

    public static func text(from list: [HM]) -> String {
        list.map(\.text).joined(separator: ", ")
    }
}

/// 사용자가 바꿀 수 있는 시각 설정.
///
/// 기본값은 `kdt-cld-6th` 기준이지만 전부 설정에서 변경 가능해야 한다.
/// 다른 기수·과정 사람도 쓸 수 있어야 하므로 하드코딩 금지.
public struct Schedule: Equatable, Codable, Sendable {
    // MARK: 메뉴바 표시

    /// 카운트다운을 시작할 시각. 이전에는 조용히 있는다.
    public var checkInWindowStart: HM
    /// 이 시각을 넘기면 지각. 카운트다운의 목표점.
    public var lateDeadline: HM
    public var classStart: HM
    public var classEnd: HM
    /// `강의실 입장` 버튼이 눌리기 시작하는 시각.
    /// 수업 시작과 별개다 — 실제로 언제 활성화되는지는 관찰해서 맞춰야 한다.
    public var classroomAvailableFrom: HM
    /// 퇴실을 안내하기 시작할 시각.
    public var checkOutRemindFrom: HM
    /// 남은 시간이 이보다 적으면 깜빡인다.
    public var urgentThreshold: TimeInterval

    // MARK: 알림

    /// 입실 알림 시각들. 마지막 것은 최종 경고로 다루어진다.
    public var checkInReminders: [HM]
    /// 강의실 입장 알림들. 한 번만 두면 놓쳤을 때 되돌릴 방법이 없다.
    public var classroomReminders: [HM]
    public var checkOutReminders: [HM]

    // MARK: 매시간 카메라 확인

    /// 카메라 확인 마감 (정각 기준 분). 매시 이 분까지 켜져 있어야 한다.
    public var photoDeadlineMinute: Int
    /// 카메라 확인 알림 (정각 기준 분). 마지막 것은 최종 안내로 다루어진다.
    public var photoReminderMinutes: [Int]
    /// 카메라 마감까지 이보다 적게 남으면 깜빡인다.
    /// 입실과 달리 창이 20분뿐이라 더 짧게 잡는다.
    public var photoUrgentThreshold: TimeInterval

    public var lunchStart: HM
    public var lunchEnd: HM

    public init(
        checkInWindowStart: HM = HM(8, 40),
        lateDeadline: HM = HM(9, 10),
        classStart: HM = HM(9, 0),
        classEnd: HM = HM(18, 0),
        classroomAvailableFrom: HM = HM(8, 50),
        checkOutRemindFrom: HM = HM(17, 57),
        urgentThreshold: TimeInterval = 5 * 60,
        checkInReminders: [HM] = [HM(8, 47), HM(8, 56), HM(9, 3), HM(9, 8)],
        classroomReminders: [HM] = [HM(8, 52), HM(9, 5)],
        checkOutReminders: [HM] = [HM(17, 57), HM(18, 5), HM(18, 15)],
        photoDeadlineMinute: Int = 20,
        photoReminderMinutes: [Int] = [2, 12],
        photoUrgentThreshold: TimeInterval = 2 * 60,
        lunchStart: HM = HM(12, 0),
        lunchEnd: HM = HM(13, 0)
    ) {
        self.checkInWindowStart = checkInWindowStart
        self.lateDeadline = lateDeadline
        self.classStart = classStart
        self.classEnd = classEnd
        self.classroomAvailableFrom = classroomAvailableFrom
        self.checkOutRemindFrom = checkOutRemindFrom
        self.urgentThreshold = urgentThreshold
        self.checkInReminders = checkInReminders
        self.classroomReminders = classroomReminders
        self.checkOutReminders = checkOutReminders
        self.photoDeadlineMinute = photoDeadlineMinute
        self.photoReminderMinutes = photoReminderMinutes
        self.photoUrgentThreshold = photoUrgentThreshold
        self.lunchStart = lunchStart
        self.lunchEnd = lunchEnd
    }

    public static let `default` = Schedule()

    /// 카메라를 켜 둬야 하는 시간대들.
    ///
    /// 수업 시간 안에서 점심시간대만 뺀다. 기본값 기준으로 9·10·11·13·14·15·16·17시 여덟 번.
    public var photoHours: [Int] {
        guard photoDeadlineMinute > 0 else { return [] }
        return (classStart.hour..<classEnd.hour).filter { hour in
            !(hour >= lunchStart.hour && hour < lunchEnd.hour)
        }
    }
}
