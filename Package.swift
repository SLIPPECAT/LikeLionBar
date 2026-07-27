// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LikeLionBar",
    platforms: [.macOS(.v14)],
    targets: [
        // 순수 로직. AppKit에 의존하지 않아 시각을 주입해 테스트할 수 있다.
        .target(
            name: "LikeLionBarCore",
            path: "Sources/LikeLionBarCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // AppKit UI. 메인 스레드 전용이라 v5 모드로 둔다.
        .executableTarget(
            name: "LikeLionBar",
            dependencies: ["LikeLionBarCore"],
            path: "Sources/LikeLionBar",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Command Line Tools 단독 환경에는 XCTest도 swift-testing 런타임도 없다.
        // 검증할 게 순수 값 비교뿐이라 프레임워크 없이 실행 파일로 돌린다.
        //   swift run CoreChecks
        .executableTarget(
            name: "CoreChecks",
            dependencies: ["LikeLionBarCore"],
            path: "Sources/CoreChecks",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
