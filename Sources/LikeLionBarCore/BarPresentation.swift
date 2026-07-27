import Foundation

/// 메뉴바에 띄울 사자 표정.
///
/// 아침이 흘러갈수록 무표정 → 화남 → 울음으로 악화된다. 숫자를 안 읽어도
/// 곁눈질만으로 상황이 전달되는 게 목적이다.
public enum Face: String, Equatable, Sendable, CaseIterable {
    case neutral  // 조용하거나 아직 여유가 있음
    case angry    // 마감이 임박했거나 남은 일이 있을 때
    case crying   // 지각 확정
    case happy    // 할 일을 마침
}

/// 메뉴바에 무엇을 어떻게 그릴지. 순수 값이라 테스트로 검증할 수 있다.
public struct BarPresentation: Equatable, Sendable {
    /// 색조. 실제 색은 UI 계층에서 결정한다.
    public enum Tone: Equatable, Sendable {
        case quiet    // 메뉴바 명암에 맡김
        case done     // 초록
        case warning  // 주황
        case alert    // 빨강
    }

    public var face: Face
    /// 아이콘 옆 텍스트. nil이면 아이콘만 표시.
    public var text: String?
    public var tone: Tone
    /// 다급한 상태. UI에서 깜빡임으로 표현한다.
    public var blinking: Bool

    public init(face: Face, text: String? = nil, tone: Tone = .quiet, blinking: Bool = false) {
        self.face = face
        self.text = text
        self.tone = tone
        self.blinking = blinking
    }
}
