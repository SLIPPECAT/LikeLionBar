import AppKit

/// 부트캠프 페이지를 Chrome으로 연다.
///
/// 로그인 세션이 Chrome에 있으므로 기본 브라우저가 아니라 Chrome을 명시적으로 쓴다.
struct Launcher {
    /// 과정 slug. 하드코딩하면 다른 기수가 못 쓰므로 설정에서 받는다.
    var courseSlug: String
    /// 로그인된 Chrome 프로필 디렉토리명 (예: "Profile 1"). 비어 있으면 기본 프로필.
    var chromeProfile: String?

    private static let chromeBundleID = "com.google.Chrome"

    var boardURL: URL {
        URL(string: "https://bootcamp.likelion.net/my/courses/detail/\(courseSlug)/board")!
    }

    /// 고용24 직업훈련 출결관리. QR 입퇴실이 거쳐가는 곳.
    var hrdURL: URL {
        URL(string: "https://www.work24.go.kr")!
    }

    func openBoard() { open(boardURL) }

    func open(_ url: URL) {
        guard let chrome = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Self.chromeBundleID
        ) else {
            // Chrome이 없으면 기본 브라우저로라도 연다.
            NSWorkspace.shared.open(url)
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if let profile = chromeProfile, !profile.isEmpty {
            // 주의: Chrome이 이미 떠 있으면 이 인자가 무시될 수 있다.
            // 그때는 사용자가 Chrome에서 해당 프로필 창을 활성화해 둬야 한다.
            config.arguments = ["--profile-directory=\(profile)"]
        }

        NSWorkspace.shared.open(
            [url], withApplicationAt: chrome, configuration: config, completionHandler: nil
        )
    }
}
