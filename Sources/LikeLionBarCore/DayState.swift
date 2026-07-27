import Foundation

/// 하루에 처리해야 하는 단계.
public enum Step: String, Codable, CaseIterable, Sendable {
    case checkIn    // QR 입실
    case classroom  // 강의실 입장
    case camera     // 카메라 확인
    case checkOut   // QR 퇴실

    public var label: String {
        switch self {
        case .checkIn:   return "QR 입실"
        case .classroom: return "강의실 입장"
        case .camera:    return "카메라 확인"
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
    /// 완료된 단계와 완료 시각.
    public var completed: [Step: Date]
    /// 공휴일·개인사정 등으로 오늘은 쉬는 날.
    public var isDayOff: Bool

    public init(day: DateComponents, completed: [Step: Date] = [:], isDayOff: Bool = false) {
        self.day = day
        self.completed = completed
        self.isDayOff = isDayOff
    }

    public func isDone(_ step: Step) -> Bool { completed[step] != nil }

    public mutating func complete(_ step: Step, at date: Date) {
        completed[step] = date
    }

    public mutating func uncomplete(_ step: Step) {
        completed[step] = nil
    }

    /// 오늘 시작한 흔적이 있는지. 조용한 상태에서 ✅를 보일지 결정할 때 쓴다.
    public var hasAnyProgress: Bool { !completed.isEmpty }

    public static func empty(for date: Date, calendar: Calendar) -> DayState {
        DayState(day: calendar.dateComponents([.year, .month, .day], from: date))
    }
}
