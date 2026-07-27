import AppKit

/// 같은 앱이 둘 이상 뜨지 않게 막는다.
///
/// 두 개가 돌면 알림이 두 번 오고, 같은 `state.json`을 서로 덮어써서 완료 표시가
/// 사라진다. Finder에서 더블클릭하면 LaunchServices가 막아주지만, 사본이 두 군데
/// 있거나 `open -n`으로 띄우면 그대로 뚫린다.
enum SingleInstance {
    /// 이미 다른 인스턴스가 돌고 있으면 true. 그 경우 곧바로 종료해야 한다.
    static func anotherIsRunning() -> Bool {
        // 미리보기 모드는 개발 중 실제 인스턴스와 나란히 띄워 비교하므로 예외로 둔다.
        guard !DebugClock.isActive else { return false }
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }

        let mine = NSRunningApplication.current.processIdentifier
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != mine }

        guard let other = others.first else { return false }

        Log.write("이미 실행 중이라 종료한다 (기존 pid \(other.processIdentifier))")
        // 사용자가 직접 다시 실행했다면 뭔가 보고 싶었을 테니 기존 것을 앞으로 꺼낸다.
        other.activate()
        return true
    }
}
