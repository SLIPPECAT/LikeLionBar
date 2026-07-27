import Foundation
import LikeLionBarCore

/// 파일 로그.
///
/// 유니파이드 로그는 서명·권한 상태에 따라 잡히지 않을 때가 있어 진단이 어렵다.
/// 배포 후 동기들이 문제를 겪을 때도 이 파일 하나면 상황을 알 수 있다.
enum Log {
    private static let queue = DispatchQueue(label: "LikeLionBar.log")

    private static let url: URL = {
        let dir = StateStore.defaultDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("debug.log")
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ message: String) {
        NSLog("LikeLionBar: \(message)")
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            rotateIfNeeded()
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    /// 이 크기를 넘으면 한 번 넘기고 새로 쓴다. 매일 도는 앱이라 놔두면 계속 쌓인다.
    private static let maxBytes = 512 * 1024

    /// 직전 파일 하나만 남긴다. 문제를 볼 땐 보통 최근 것이면 충분하다.
    private static func rotateIfNeeded() {
        let fm = FileManager.default
        guard let size = try? fm.attributesOfItem(atPath: url.path)[.size] as? Int,
              size > maxBytes else { return }

        let previous = url.deletingLastPathComponent().appendingPathComponent("debug.log.1")
        try? fm.removeItem(at: previous)
        try? fm.moveItem(at: url, to: previous)
    }
}
