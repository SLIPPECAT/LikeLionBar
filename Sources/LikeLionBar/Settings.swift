import Foundation
import LikeLionBarCore

/// 사용자 설정.
///
/// 과정 slug와 시각을 하드코딩하면 다른 기수·과정 사람이 쓸 수 없다.
/// 배포가 전제이므로 값은 전부 밖으로 빼둔다.
enum Settings {
    private static let defaults = UserDefaults.standard

    /// 설정이 바뀌면 엔진을 다시 만들어야 한다.
    static let didChange = Notification.Name("LikeLionBar.settingsDidChange")

    private enum Key {
        static let courseSlug = "courseSlug"
        static let chromeProfile = "chromeProfile"
        static let notificationSound = "notificationSound"
        static let customReminders = "customReminders"
        static let useHolidayCalendar = "useHolidayCalendar"

        static let photoDeadlineMinute = "photoDeadlineMinute"
        static let photoReminderMinutes = "photoReminderMinutes"

        static let checkInWindowStart = "checkInWindowStart"
        static let lateDeadline = "lateDeadline"
        static let classStart = "classStart"
        static let classEnd = "classEnd"
        static let classroomAvailableFrom = "classroomAvailableFrom"
        static let checkOutRemindFrom = "checkOutRemindFrom"

        static let checkInReminders = "checkInReminders"
        static let classroomReminders = "classroomReminders"
        static let checkOutReminders = "checkOutReminders"
        static let lunchStart = "lunchStart"
        static let lunchEnd = "lunchEnd"

        static let allSchedule = [
            checkInWindowStart, lateDeadline, classStart, classEnd,
            classroomAvailableFrom, checkOutRemindFrom, checkInReminders,
            classroomReminders, checkOutReminders,
            photoDeadlineMinute, photoReminderMinutes,
            lunchStart, lunchEnd,
        ]
    }

    /// 공휴일을 받아와 자동으로 쉬는 날 처리할지. 끄면 네트워크 요청도 하지 않는다.
    static var useHolidayCalendar: Bool {
        get { defaults.object(forKey: Key.useHolidayCalendar) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.useHolidayCalendar) }
    }

    /// 기본은 팝업만. 소리는 켠 사람만 받는다.
    static var notificationSound: Bool {
        get { defaults.bool(forKey: Key.notificationSound) }
        set { defaults.set(newValue, forKey: Key.notificationSound) }
    }

    /// 사용자가 직접 등록한 알림들.
    static var customReminders: [CustomReminder] {
        get {
            guard let data = defaults.data(forKey: Key.customReminders) else { return [] }
            let decoder = JSONDecoder()
            return (try? decoder.decode([CustomReminder].self, from: data)) ?? []
        }
        set {
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(newValue) else { return }
            defaults.set(data, forKey: Key.customReminders)
        }
    }

    /// 날짜가 지난 일회성 알림을 치운다. 놔두면 설정 목록이 계속 길어진다.
    @discardableResult
    static func pruneExpiredReminders(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let all = customReminders
        let kept = all.filter { !$0.isExpired(on: now, calendar: calendar) }
        guard kept.count != all.count else { return 0 }
        customReminders = kept
        return all.count - kept.count
    }

    static var courseSlug: String {
        get { defaults.string(forKey: Key.courseSlug) ?? "kdt-cld-6th" }
        set { defaults.set(newValue, forKey: Key.courseSlug) }
    }

    /// 로그인된 Chrome 프로필 디렉토리명. 빈 문자열이면 Chrome 기본 프로필.
    static var chromeProfile: String {
        get { defaults.string(forKey: Key.chromeProfile) ?? "" }
        set { defaults.set(newValue, forKey: Key.chromeProfile) }
    }

    /// 저장된 값으로 조립한 일정. 값이 없거나 형식이 깨졌으면 기본값으로 되돌아간다.
    static var schedule: Schedule {
        get {
            let d = Schedule.default
            return Schedule(
                checkInWindowStart: time(Key.checkInWindowStart, d.checkInWindowStart),
                lateDeadline: time(Key.lateDeadline, d.lateDeadline),
                classStart: time(Key.classStart, d.classStart),
                classEnd: time(Key.classEnd, d.classEnd),
                classroomAvailableFrom: time(Key.classroomAvailableFrom, d.classroomAvailableFrom),
                checkOutRemindFrom: time(Key.checkOutRemindFrom, d.checkOutRemindFrom),
                checkInReminders: times(Key.checkInReminders, d.checkInReminders),
                classroomReminders: times(Key.classroomReminders, d.classroomReminders),
                checkOutReminders: times(Key.checkOutReminders, d.checkOutReminders),
                photoDeadlineMinute: defaults.object(forKey: Key.photoDeadlineMinute) as? Int
                    ?? d.photoDeadlineMinute,
                photoReminderMinutes: minutes(Key.photoReminderMinutes, d.photoReminderMinutes),
                lunchStart: time(Key.lunchStart, d.lunchStart),
                lunchEnd: time(Key.lunchEnd, d.lunchEnd)
            )
        }
        set {
            defaults.set(newValue.checkInWindowStart.text, forKey: Key.checkInWindowStart)
            defaults.set(newValue.lateDeadline.text, forKey: Key.lateDeadline)
            defaults.set(newValue.classStart.text, forKey: Key.classStart)
            defaults.set(newValue.classEnd.text, forKey: Key.classEnd)
            defaults.set(newValue.classroomAvailableFrom.text, forKey: Key.classroomAvailableFrom)
            defaults.set(newValue.checkOutRemindFrom.text, forKey: Key.checkOutRemindFrom)
            defaults.set(HM.text(from: newValue.checkInReminders), forKey: Key.checkInReminders)
            defaults.set(HM.text(from: newValue.classroomReminders), forKey: Key.classroomReminders)
            defaults.set(HM.text(from: newValue.checkOutReminders), forKey: Key.checkOutReminders)
            defaults.set(newValue.photoDeadlineMinute, forKey: Key.photoDeadlineMinute)
            defaults.set(
                newValue.photoReminderMinutes.map(String.init).joined(separator: ", "),
                forKey: Key.photoReminderMinutes
            )
            defaults.set(newValue.lunchStart.text, forKey: Key.lunchStart)
            defaults.set(newValue.lunchEnd.text, forKey: Key.lunchEnd)
        }
    }

    static func resetSchedule() {
        for key in Key.allSchedule { defaults.removeObject(forKey: key) }
    }

    static func notifyChanged() {
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    // MARK: - 도우미

    private static func time(_ key: String, _ fallback: HM) -> HM {
        defaults.string(forKey: key).flatMap(HM.init(text:)) ?? fallback
    }

    private static func times(_ key: String, _ fallback: [HM]) -> [HM] {
        guard let raw = defaults.string(forKey: key) else { return fallback }
        let parsed = HM.list(from: raw)
        // 전부 지워버리면 알림이 통째로 사라진다. 그건 사고지 의도가 아니다.
        return parsed.isEmpty ? fallback : parsed
    }

    /// `"2, 12"` 형태의 정각 기준 분 목록.
    private static func minutes(_ key: String, _ fallback: [Int]) -> [Int] {
        guard let raw = defaults.string(forKey: key) else { return fallback }
        let parsed = raw.split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { (0..<60).contains($0) }
        return parsed.isEmpty ? fallback : parsed
    }
}
