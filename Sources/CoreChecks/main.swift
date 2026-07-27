import Foundation
import LikeLionBarCore

// ScheduleEngine 검사.
//
// 다음날 아침을 기다리지 않고 임의 시각을 주입해 하루 전체의 상태 전이를 확인한다.
// CLT 단독 환경에는 XCTest / swift-testing 런타임이 없어 하네스를 직접 둔다.
//   swift run CoreChecks

// MARK: - 하네스

var failures: [String] = []
var checkCount = 0

func expect<T: Equatable>(_ actual: T, _ expected: T, _ label: String, line: UInt = #line) {
    checkCount += 1
    guard actual != expected else { return }
    failures.append("✗ \(label)  (line \(line))\n    기대: \(expected)\n    실제: \(actual)")
}

func expectNil<T>(_ actual: T?, _ label: String, line: UInt = #line) {
    checkCount += 1
    guard let actual else { return }
    failures.append("✗ \(label)  (line \(line))\n    기대: nil\n    실제: \(actual)")
}

// MARK: - 픽스처

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
let engine = ScheduleEngine(schedule: .default, calendar: calendar)

func makeDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
    var c = DateComponents()
    (c.year, c.month, c.day, c.hour, c.minute, c.second) = (y, mo, d, h, mi, s)
    c.timeZone = calendar.timeZone
    return calendar.date(from: c)!
}

/// 2026-07-27 월요일
func monday(_ h: Int, _ m: Int, _ s: Int = 0) -> Date { makeDate(2026, 7, 27, h, m, s) }
/// 2026-08-01 토요일
func saturday(_ h: Int, _ m: Int) -> Date { makeDate(2026, 8, 1, h, m) }

func dayState(
    _ done: [Step] = [], photos: Set<Int> = [], dayOff: Bool = false, on day: Date
) -> DayState {
    var s = DayState.empty(for: day, calendar: calendar)
    s.isDayOff = dayOff
    s.donePhotoHours = photos
    for step in done { s.complete(step, at: day) }
    return s
}

func show(
    _ now: Date, _ done: [Step] = [], photos: Set<Int> = [], dayOff: Bool = false
) -> BarPresentation {
    engine.presentation(now: now, state: dayState(done, photos: photos, dayOff: dayOff, on: now))
}

// MARK: - 픽스처 전제

expect(calendar.component(.weekday, from: monday(9, 0)), 2, "2026-07-27은 월요일")
expect(calendar.component(.weekday, from: saturday(9, 0)), 7, "2026-08-01은 토요일")

// MARK: - 아침 입실

do {
    let p = show(monday(8, 39))
    expectNil(p.text, "08:40 전에는 조용하다")
    expect(p.tone, .quiet, "08:39 색조")
    expect(p.blinking, false, "08:39 깜빡임 없음")
}

do {
    let p = show(monday(8, 47))
    expect(p.text, "23:00", "08:47이면 09:10까지 23분")
    expect(p.tone, .alert, "미입실은 빨강")
    expect(p.blinking, false, "5분 넘게 남으면 깜빡이지 않는다")
}

do {
    let p = show(monday(9, 6))
    expect(p.text, "04:00", "09:06이면 4분 남음")
    expect(p.blinking, true, "5분 미만이면 깜빡인다")
}

do {
    let p = show(monday(9, 5))
    expect(p.text, "05:00", "09:05이면 정확히 5분")
    expect(p.blinking, true, "정확히 5분이면 이미 다급하다")
}

do {
    let p = show(monday(9, 11))
    expect(p.text, "지각", "마감을 넘기면 지각 표시")
    expect(p.tone, .alert, "지각은 빨강")
    expect(p.blinking, false, "이미 지각이면 깜빡임을 멈춘다")
}

do {
    // 08:50 전이라 강의실도 아직 안 조르는 구간.
    let p = show(monday(8, 45), [.checkIn])
    expectNil(p.text, "입실하면 카운트다운이 멈춘다")
    expect(p.tone, .done, "입실 후에는 초록")
}

// MARK: - 강의실 입장

do {
    let p = show(monday(9, 30), [.checkIn])
    expect(p.text, "강의실", "수업 시작 후 강의실 입장을 조른다")
    expect(p.tone, .warning, "강의실은 주황")
}

do {
    // 버튼이 08:50부터 눌린다는 전제. 그 전에는 조르지 않는다.
    let p = show(monday(8, 45), [.checkIn])
    expectNil(p.text, "버튼 활성화 전에는 강의실을 조르지 않는다")
}

do {
    let p = show(monday(8, 52), [.checkIn])
    expect(p.text, "강의실", "08:50이 지나면 수업 시작 전이라도 조른다")
}

do {
    // 활성화 시각은 관찰 결과에 따라 설정에서 바뀔 수 있어야 한다.
    var late = Schedule.default
    late.classroomAvailableFrom = HM(9, 30)
    let e = ScheduleEngine(schedule: late, calendar: calendar)
    let now = monday(9, 10)
    let p = e.presentation(now: now, state: dayState([.checkIn], on: now))
    expectNil(p.text, "활성화 시각을 늦추면 그 전에는 조르지 않는다")
}

// MARK: - 점심 / 수업 중

do {
    let p = show(monday(12, 30), [.checkIn, .classroom])
    expectNil(p.text, "점심에는 조용하다")
    expect(p.tone, .done, "점심 색조")
}

// MARK: - 퇴실

do {
    let p = show(monday(17, 58), [.checkIn, .classroom])
    expect(p.text, "퇴실", "17:57부터 퇴실을 조른다")
    expect(p.tone, .warning, "퇴실은 주황")
}

do {
    let p = show(monday(18, 5), [.checkIn, .classroom, .checkOut])
    expectNil(p.text, "퇴실하면 조용해진다")
    expect(p.tone, .done, "퇴실 후 색조")
}

do {
    // 퇴실을 놓치면 그날 출석이 통째로 날아가므로 밤까지 계속 보여준다.
    let p = show(monday(22, 0), [.checkIn, .classroom])
    expect(p.text, "퇴실", "밤 10시에도 퇴실 미완료면 계속 표시")
}

// MARK: - 우선순위

do {
    let p = show(monday(9, 30))
    expect(p.text, "지각", "입실이 안 됐으면 강의실보다 그게 먼저다")
}

do {
    // 수업이 끝난 뒤까지 '지각'을 띄우는 건 의미가 없다.
    let p = show(monday(18, 30))
    expect(p.text, "퇴실", "수업 종료 후에는 지각 대신 퇴실로 넘어간다")
}

// MARK: - 쉬는 날

do {
    let p = show(saturday(8, 47))
    expectNil(p.text, "토요일에는 조르지 않는다")
    expect(p.tone, .quiet, "주말 색조")
}

do {
    let p = show(monday(8, 47), dayOff: true)
    expectNil(p.text, "쉬는 날로 표시하면 조용하다")
}

// MARK: - 포맷

expect(ScheduleEngine.countdown(1380), "23:00", "23분 포맷")
expect(ScheduleEngine.countdown(272), "04:32", "4분 32초 포맷")
expect(ScheduleEngine.countdown(59), "00:59", "1분 미만 포맷")
expect(ScheduleEngine.countdown(0), "00:00", "0 포맷")
expect(ScheduleEngine.countdown(-10), "00:00", "음수는 0으로 눌러준다")
// 0.5초 남았는데 00:00을 보이면 아직 시간이 있는데 끝난 것처럼 보인다.
expect(ScheduleEngine.countdown(0.5), "00:01", "올림해서 조기 0을 막는다")

// MARK: - 사자 표정 (무표정 → 화남 → 울음으로 악화)

expect(show(monday(8, 39)).face, .neutral, "조용할 땐 무표정")
expect(show(saturday(8, 47)).face, .neutral, "주말도 무표정")
expect(show(monday(8, 47), dayOff: true).face, .neutral, "쉬는 날도 무표정")
expect(show(monday(8, 47)).face, .neutral, "여유 있는 카운트다운은 아직 무표정")
expect(show(monday(9, 6)).face, .angry, "5분 미만이면 화난다")
expect(show(monday(9, 5)).face, .angry, "정확히 5분에서 화난다")
expect(show(monday(9, 11)).face, .crying, "지각하면 운다")
expect(show(monday(9, 30), [.checkIn]).face, .angry, "강의실 재촉은 화난 얼굴")
expect(show(monday(17, 58), [.checkIn, .classroom]).face, .angry, "퇴실 재촉도 화난 얼굴")
expect(show(monday(8, 45), [.checkIn]).face, .happy, "할 일을 마치면 웃는다")
expect(show(monday(18, 5), [.checkIn, .classroom, .checkOut]).face, .happy, "퇴실까지 끝내면 웃는다")

do {
    // 표정이 바뀌는 순간 색도 같이 바뀌어야 신호가 어긋나지 않는다
    expect(show(monday(9, 6)).tone, .alert, "화난 입실 독촉은 빨강")
    expect(show(monday(9, 11)).tone, .alert, "지각도 빨강")
    expect(show(monday(9, 30), [.checkIn]).tone, .warning, "강의실은 주황")
    expect(show(monday(18, 5), [.checkIn, .classroom, .checkOut]).tone, .done, "완료는 초록")
}

// MARK: - 사진 대상 시간대

do {
    let hours = Schedule.default.photoHours
    expect(hours, [9, 10, 11, 13, 14, 15, 16, 17], "수업 시간에서 점심시간대만 뺀 여덟 번")
    expect(hours.contains(12), false, "12시대는 점심이라 건너뛴다")
    expect(hours.contains(18), false, "수업이 끝난 뒤는 없다")
    expect(hours.contains(8), false, "수업 시작 전은 없다")

    var off = Schedule.default
    off.photoDeadlineMinute = 0
    expect(off.photoHours.isEmpty, true, "마감을 0으로 두면 사진을 끈다")

    // 점심시간을 바꾸면 건너뛰는 시간대도 따라가야 한다
    var lateLunch = Schedule.default
    lateLunch.lunchStart = HM(13, 0)
    lateLunch.lunchEnd = HM(14, 0)
    expect(lateLunch.photoHours.contains(12), true, "점심을 옮기면 12시대가 살아난다")
    expect(lateLunch.photoHours.contains(13), false, "옮긴 점심시간대는 빠진다")
}

// MARK: - ReminderEngine

let reminders = ReminderEngine(schedule: .default, calendar: calendar)

func due(
    _ h: Int, _ m: Int, _ done: [Step] = [], photos: Set<Int> = [],
    dayOff: Bool = false, on day: (Int, Int, Int)? = nil
) -> [Reminder] {
    let to = day.map { makeDate($0.0, $0.1, $0.2, h, m, 30) } ?? monday(h, m, 30)
    let from = to.addingTimeInterval(-60)
    return reminders.due(
        from: from, to: to, state: dayState(done, photos: photos, dayOff: dayOff, on: to)
    )
}

/// 사진 알림이 매시간 도는지 보려면 그 시간대만 안 찍은 상태를 만들어야 한다.
let allPhotoHours = Set(Schedule.default.photoHours)
func photosExcept(_ hour: Int) -> Set<Int> { allPhotoHours.subtracting([hour]) }

expect(due(8, 47), [.checkIn(attempt: 1, isFinal: false)], "08:47에 첫 입실 알림")
expect(due(9, 8), [.checkIn(attempt: 4, isFinal: true)], "09:08은 최종 경고")
expect(due(8, 47, [.checkIn]).isEmpty, true, "입실했으면 입실 알림이 없다")
expect(due(8, 52, [.checkIn]), [.classroom], "입실 후 강의실 알림")
expect(due(8, 52).isEmpty, true, "입실 전에는 강의실을 조르지 않는다")
expect(due(17, 57, [.checkIn, .classroom]), [.checkOut(attempt: 1)], "17:57에 퇴실 알림")
expect(due(18, 15, [.checkIn, .classroom, .checkOut]).isEmpty, true, "퇴실했으면 알림이 없다")
expect(due(8, 47, dayOff: true).isEmpty, true, "쉬는 날에는 알림이 없다")
// 2026-08-01 토요일
expect(due(8, 47, on: (2026, 8, 1)).isEmpty, true, "주말에는 알림이 없다")
expect(due(8, 48).isEmpty, true, "알림 시각이 아니면 조용하다")

// MARK: - 매시간 사진 알림

do {
    let done = [Step.checkIn, .classroom]
    // 10시대만 안 찍은 상태
    expect(due(10, 2, done, photos: photosExcept(10)), [.photo(hour: 10, isFinal: false)],
           "매시 :02에 첫 사진 알림")
    expect(due(10, 12, done, photos: photosExcept(10)), [.photo(hour: 10, isFinal: true)],
           ":12는 마감 전 최종 경고")
    expect(due(10, 2, done, photos: allPhotoHours).isEmpty, true,
           "이미 찍었으면 알리지 않는다")
    expect(due(10, 20, done, photos: photosExcept(10)).isEmpty, true,
           "마감 시각 자체에는 알리지 않는다")
    expect(due(12, 2, done, photos: photosExcept(12)).isEmpty, true,
           "점심시간대에는 사진을 조르지 않는다")
    expect(due(18, 2, done, photos: []).isEmpty, true,
           "수업이 끝난 뒤에는 조르지 않는다")
    expect(due(15, 2, done, photos: photosExcept(15)), [.photo(hour: 15, isFinal: false)],
           "오후에도 시간마다 되풀이된다")

    // 시간대별로 따로 세므로 앞 시간을 찍었다고 다음 시간이 면제되지 않는다
    expect(due(11, 2, done, photos: [9, 10]), [.photo(hour: 11, isFinal: false)],
           "앞 시간을 찍어도 이번 시간은 다시 조른다")
}

// MARK: - 메뉴바 사진 카운트다운

do {
    let done = [Step.checkIn, .classroom]
    expectNil(show(monday(10, 5), done, photos: photosExcept(10)).text,
              "첫 알림 직후에는 메뉴바가 조용하다")

    let p = show(monday(10, 14), done, photos: photosExcept(10))
    expect(p.text, "사진 06:00", ":12를 지나면 마감까지 카운트다운")
    expect(p.tone, .alert, "사진 독촉은 빨강")
    expect(p.face, .angry, "사진 독촉은 화난 얼굴")
    expect(p.blinking, false, "2분 넘게 남으면 깜빡이지 않는다")

    expect(show(monday(10, 19), done, photos: photosExcept(10)).blinking, true,
           "2분 미만이면 깜빡인다")
    expectNil(show(monday(10, 21), done, photos: photosExcept(10)).text,
              "마감이 지나면 이번 시간은 포기하고 조용해진다")
    expectNil(show(monday(10, 14), done, photos: allPhotoHours).text,
              "찍었으면 즉시 조용해진다")
    expectNil(show(monday(12, 14), done, photos: photosExcept(12)).text,
              "점심시간대에는 카운트다운이 없다")

    // 입실이 더 급하다. 사진 때문에 지각 경고가 가려지면 안 된다
    expect(show(monday(9, 14), photos: photosExcept(9)).text, "지각",
           "미입실이 사진보다 우선한다")
}

do {
    // 경계: 정확히 그 초에 걸쳐야 하고 중복으로 두 번 울리면 안 된다
    let at = monday(8, 47, 0)
    let before = reminders.due(from: at.addingTimeInterval(-1), to: at, state: dayState(on: at))
    let after = reminders.due(from: at, to: at.addingTimeInterval(1), state: dayState(on: at))
    expect(before.count, 1, "알림 시각을 지나는 순간 한 번 울린다")
    expect(after.isEmpty, true, "이미 지난 시각을 다시 울리지 않는다")
}

// MARK: - StateStore (영속화 · 날짜 롤오버)

do {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("LikeLionBarChecks-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let mon = monday(8, 52)
    let nextDay = makeDate(2026, 7, 28, 8, 0)

    let a = StateStore(directory: tmp, calendar: calendar, now: mon)
    a.complete(.checkIn, at: mon)
    expect(a.state.isDone(.checkIn), true, "완료 표시가 반영된다")

    // 앱을 껐다 켜는 상황
    let b = StateStore(directory: tmp, calendar: calendar, now: mon)
    expect(b.state.isDone(.checkIn), true, "재시작해도 오늘 상태가 유지된다")

    // 어제 상태를 오늘로 들고 오면 안 된다
    let c = StateStore(directory: tmp, calendar: calendar, now: nextDay)
    expect(c.state.isDone(.checkIn), false, "날짜가 바뀌면 새 하루로 리셋된다")

    // 자정을 넘겨 켜둔 채 다음날을 맞는 경우
    let d = StateStore(directory: tmp, calendar: calendar, now: mon)
    d.complete(.checkIn, at: mon)
    expect(d.rollOverIfNeeded(now: mon), false, "같은 날에는 롤오버하지 않는다")
    expect(d.rollOverIfNeeded(now: nextDay), true, "다음날이 되면 롤오버한다")
    expect(d.state.isDone(.checkIn), false, "롤오버 후에는 비어 있다")

    let e = StateStore(directory: tmp, calendar: calendar, now: mon)
    e.toggle(.checkOut, at: mon)
    expect(e.state.isDone(.checkOut), true, "토글로 완료된다")
    e.toggle(.checkOut, at: mon)
    expect(e.state.isDone(.checkOut), false, "다시 토글하면 취소된다")

    let f = StateStore(directory: tmp, calendar: calendar, now: mon)
    f.setDayOff(true, at: mon)
    let g = StateStore(directory: tmp, calendar: calendar, now: mon)
    expect(g.state.isDayOff, true, "쉬는 날 표시가 유지된다")

    let logLines = (try? String(contentsOf: tmp.appendingPathComponent("log.jsonl"), encoding: .utf8))?
        .split(separator: "\n").count ?? 0
    expect(logLines > 0, true, "log.jsonl에 이력이 남는다")

    let raw = (try? String(contentsOf: tmp.appendingPathComponent("state.json"), encoding: .utf8)) ?? ""
    expect(raw.contains("isDayOff"), true, "state.json이 사람이 읽을 수 있는 형태다")
}

// MARK: - 커스텀 알림

do {
    let monDay = calendar.dateComponents([.year, .month, .day], from: monday(0, 0))
    let hospital = CustomReminder(time: HM(13, 40), title: "병원", isDaily: false, day: monDay)
    let stretch = CustomReminder(time: HM(15, 10), title: "스트레칭", isDaily: true)

    let engine2 = ReminderEngine(
        schedule: .default, custom: [hospital, stretch], calendar: calendar
    )
    func customDue(_ h: Int, _ m: Int, dayOff: Bool = false, on day: (Int, Int, Int)? = nil) -> [Reminder] {
        let to = day.map { makeDate($0.0, $0.1, $0.2, h, m, 30) } ?? monday(h, m, 30)
        let state = dayState([.checkIn, .classroom], photos: allPhotoHours, dayOff: dayOff, on: to)
        return engine2.due(from: to.addingTimeInterval(-60), to: to, state: state)
    }

    expect(customDue(13, 40), [.custom(title: "병원")], "등록한 시각에 울린다")
    expect(customDue(15, 10), [.custom(title: "스트레칭")], "매 평일 알림도 울린다")
    expect(customDue(13, 41).isEmpty, true, "시각이 아니면 조용하다")

    // 쉬는 날: 개인 일정은 살고 반복 일정은 쉰다
    expect(customDue(13, 40, dayOff: true), [.custom(title: "병원")],
           "쉬는 날이어도 그날 잡은 개인 일정은 울린다")
    expect(customDue(15, 10, dayOff: true).isEmpty, true,
           "쉬는 날에는 매 평일 반복을 쉰다")

    // 주말: 일회성은 그날이 아니므로 안 울리고, 반복도 평일이 아니라 쉰다
    expect(customDue(13, 40, on: (2026, 8, 1)).isEmpty, true, "다른 날짜에는 안 울린다")
    expect(customDue(15, 10, on: (2026, 8, 1)).isEmpty, true, "주말에는 반복도 쉰다")

    // 꺼두면 울리지 않는다
    var off = hospital
    off.isEnabled = false
    let engine3 = ReminderEngine(schedule: .default, custom: [off], calendar: calendar)
    let at = monday(13, 40, 30)
    expect(engine3.due(from: at.addingTimeInterval(-60), to: at,
                       state: dayState(on: at)).isEmpty, true, "꺼둔 알림은 울리지 않는다")

    // 만료 판정
    expect(hospital.isExpired(on: monday(23, 0), calendar: calendar), false, "당일에는 안 지났다")
    expect(hospital.isExpired(on: makeDate(2026, 7, 28, 0, 1), calendar: calendar), true,
           "다음날이 되면 지난 것으로 본다")
    expect(stretch.isExpired(on: makeDate(2027, 1, 1, 0, 0), calendar: calendar), false,
           "반복 알림은 만료되지 않는다")
}

do {
    // 출결 알림과 섞여도 서로 지워지지 않아야 한다
    let lunch = CustomReminder(time: HM(8, 47), title: "약 먹기", isDaily: true)
    let engine4 = ReminderEngine(schedule: .default, custom: [lunch], calendar: calendar)
    let at = monday(8, 47, 30)
    let result = engine4.due(from: at.addingTimeInterval(-60), to: at, state: dayState(on: at))
    expect(result.count, 2, "같은 시각의 출결 알림과 내 알림이 둘 다 나온다")
    expect(result.contains(.custom(title: "약 먹기")), true, "내 알림이 포함된다")
    expect(result.contains(.checkIn(attempt: 1, isFinal: false)), true, "입실 알림도 포함된다")
}

// MARK: - HM 문자열 (설정 창 입력)

expect(HM(text: "08:47"), HM(8, 47), "표준 형식을 읽는다")
expect(HM(text: "8:5"), HM(8, 5), "한 자리도 읽는다")
expect(HM(text: " 09:10 "), HM(9, 10), "앞뒤 공백을 무시한다")
expectNil(HM(text: "25:00"), "24시 이상은 거부한다")
expectNil(HM(text: "08:60"), "60분 이상은 거부한다")
expectNil(HM(text: "아무거나"), "숫자가 아니면 거부한다")
expectNil(HM(text: "0847"), "구분자가 없으면 거부한다")
expect(HM(8, 47).text, "08:47", "두 자리로 채워 쓴다")
expect(HM(18, 5).text, "18:05", "분도 두 자리")
expect(HM.list(from: "08:47, 08:56, 09:03"), [HM(8, 47), HM(8, 56), HM(9, 3)], "쉼표 목록을 읽는다")
expect(HM.list(from: "08:47, 이상한값"), [HM(8, 47)], "깨진 항목만 버린다")
expect(HM.list(from: "").isEmpty, true, "빈 문자열은 빈 목록")
expect(HM.text(from: [HM(17, 57), HM(18, 5)]), "17:57, 18:05", "목록을 문자열로 되돌린다")

do {
    // 왕복해도 값이 변하지 않아야 설정 창에서 저장·재열기가 안전하다
    let original = Schedule.default.checkInReminders
    expect(HM.list(from: HM.text(from: original)), original, "목록 왕복이 보존된다")
}

// MARK: - 결과

if failures.isEmpty {
    print("✓ 검사 \(checkCount)개 모두 통과")
    exit(0)
} else {
    for f in failures { print(f) }
    print("\n✗ \(failures.count)/\(checkCount) 실패")
    exit(1)
}
