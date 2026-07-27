import Foundation

/// 하루에 처리해야 하는 단계.
public enum Step: String, Codable, CaseIterable, Sendable {
    case checkIn    // QR 입실
    case classroom  // 강의실 입장
    case camera     // 매시간 사진 (하루 한 번이 아니라 시간마다)
    case checkOut   // QR 퇴실

    public var label: String {
        switch self {
        case .checkIn:   return "QR 입실"
        case .classroom: return "강의실 입장"
        case .camera:    return "이번 시간 사진"
        case .checkOut:  return "QR 퇴실"
        }
    }
}

// 이게 없으면 [Step: Date]가 키/값이 번갈아 나오는 배열로 저장돼 state.json을
// 사람이 읽기 어려워진다. 문자열 키를 가진 객체로 저장되게 한다.
extension Step: CodingKeyRepresentable {}

/// 하루치 진행 상황.
public struct DayState: Equatable, Codable, Sendable {
    /// 이 상태가 어느 날짜의 것인지. 날짜가 바뀌면 리셋한다.
    public var day: DateComponents
    /// 완료된 단계와 완료 시각. 사진은 시간마다라 여기 들어가지 않는다.
    public var completed: [Step: Date]
    /// 사진을 찍은 시간대들. 매시 마감이 따로 있어 하루 단위로는 표현할 수 없다.
    public var donePhotoHours: Set<Int>
    /// 공휴일·개인사정 등으로 오늘은 쉬는 날.
    public var isDayOff: Bool
    /// 자동으로 쉬는 날 처리된 사유 (예: "설날"). 직접 켠 경우엔 nil.
    public var autoDayOffReason: String?
    /// 사용자가 자동 처리를 직접 되돌렸는지.
    ///
    /// 부트캠프가 공휴일에도 수업하는 경우가 있다. 한 번 되돌렸으면 그날은
    /// 다시 자동으로 켜지 않는다 — 껐는데 계속 켜지면 고장으로 보인다.
    public var dayOffOverridden: Bool

    public init(
        day: DateComponents,
        completed: [Step: Date] = [:],
        donePhotoHours: Set<Int> = [],
        isDayOff: Bool = false,
        autoDayOffReason: String? = nil,
        dayOffOverridden: Bool = false
    ) {
        self.day = day
        self.completed = completed
        self.donePhotoHours = donePhotoHours
        self.isDayOff = isDayOff
        self.autoDayOffReason = autoDayOffReason
        self.dayOffOverridden = dayOffOverridden
    }

    // 이전 버전이 저장한 state.json에는 donePhotoHours가 없다. 통째로 못 읽으면
    // 업데이트 직후 오늘 진행 상황이 날아가므로, 없는 항목은 빈 값으로 받는다.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(DateComponents.self, forKey: .day)
        completed = try c.decodeIfPresent([Step: Date].self, forKey: .completed) ?? [:]
        donePhotoHours = try c.decodeIfPresent(Set<Int>.self, forKey: .donePhotoHours) ?? []
        isDayOff = try c.decodeIfPresent(Bool.self, forKey: .isDayOff) ?? false
        autoDayOffReason = try c.decodeIfPresent(String.self, forKey: .autoDayOffReason)
        dayOffOverridden = try c.decodeIfPresent(Bool.self, forKey: .dayOffOverridden) ?? false
    }

    public func isDone(_ step: Step) -> Bool { completed[step] != nil }

    public mutating func complete(_ step: Step, at date: Date) {
        completed[step] = date
    }

    public mutating func uncomplete(_ step: Step) {
        completed[step] = nil
    }

    // MARK: 사진

    public func isPhotoDone(hour: Int) -> Bool { donePhotoHours.contains(hour) }

    public mutating func togglePhoto(hour: Int) {
        if donePhotoHours.contains(hour) {
            donePhotoHours.remove(hour)
        } else {
            donePhotoHours.insert(hour)
        }
    }

    public mutating func completePhoto(hour: Int) {
        donePhotoHours.insert(hour)
    }

    /// 오늘 시작한 흔적이 있는지. 조용한 상태에서 웃는 얼굴을 보일지 결정할 때 쓴다.
    public var hasAnyProgress: Bool { !completed.isEmpty || !donePhotoHours.isEmpty }

    public static func empty(for date: Date, calendar: Calendar) -> DayState {
        DayState(day: calendar.dateComponents([.year, .month, .day], from: date))
    }
}
