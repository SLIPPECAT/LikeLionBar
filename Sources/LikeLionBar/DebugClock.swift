import Foundation
import LikeLionBarCore

/// 개발·미리보기용 가짜 시각.
///
/// 아침 상태를 확인하려고 다음날까지 기다릴 수는 없다. 시작 시각만 가짜로 주고
/// 이후로는 실제 시간과 같은 속도로 흐르게 해서 카운트다운과 깜빡임을 그대로 본다.
///
///     LIKELIONBAR_FAKE_TIME=2026-07-27T09:06:00 \
///     LIKELIONBAR_FAKE_DONE=checkIn \
///     ./build/LikeLionBar.app/Contents/MacOS/LikeLionBar
enum DebugClock {
    static var isActive: Bool {
        ProcessInfo.processInfo.environment["LIKELIONBAR_FAKE_TIME"] != nil
    }

    /// 미리보기 모드에서 쓸 저장 위치. 실제 출결 기록을 오염시키면 안 된다.
    /// nil이면 StateStore가 기본 위치를 쓴다.
    static var previewDirectory: URL? {
        guard isActive else { return nil }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LikeLionBarPreview", isDirectory: true)
        // 미리보기는 매번 깨끗한 상태에서 시작해야 예측 가능하다.
        try? FileManager.default.removeItem(at: dir)
        return dir
    }

    static func makeNowProvider() -> () -> Date {
        guard let raw = ProcessInfo.processInfo.environment["LIKELIONBAR_FAKE_TIME"] else {
            return { Date() }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.locale = Locale(identifier: "en_US_POSIX")

        guard let fakeStart = formatter.date(from: raw) else {
            NSLog("LikeLionBar: LIKELIONBAR_FAKE_TIME 파싱 실패 (\(raw)) — 실제 시각을 쓴다")
            return { Date() }
        }

        let realStart = Date()
        NSLog("LikeLionBar: 가짜 시각 모드 — \(raw) 부터 시작")
        return { fakeStart.addingTimeInterval(Date().timeIntervalSince(realStart)) }
    }

    /// `LIKELIONBAR_FAKE_DONE=checkIn,classroom` 형태로 완료 단계를 미리 채운다.
    static func fakeCompletedSteps() -> [Step] {
        guard let raw = ProcessInfo.processInfo.environment["LIKELIONBAR_FAKE_DONE"] else {
            return []
        }
        return raw
            .split(separator: ",")
            .compactMap { Step(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
    }
}
