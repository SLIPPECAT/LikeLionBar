import Foundation

/// 메뉴바에 무엇을 어떻게 그릴지. 순수 값이라 테스트로 검증할 수 있다.
public struct BarPresentation: Equatable, Sendable {
    /// 색조. 실제 색은 UI 계층에서 결정한다.
    public enum Tone: Equatable, Sendable {
        case quiet    // 기본 (템플릿 색)
        case done     // 초록
        case warning  // 주황
        case alert    // 빨강
    }

    /// SF Symbol 이름.
    public var symbol: String
    /// 아이콘 옆 텍스트. nil이면 아이콘만 표시.
    public var text: String?
    public var tone: Tone
    /// 다급한 상태. UI에서 깜빡임으로 표현한다.
    public var blinking: Bool

    public init(symbol: String, text: String? = nil, tone: Tone = .quiet, blinking: Bool = false) {
        self.symbol = symbol
        self.text = text
        self.tone = tone
        self.blinking = blinking
    }
}
