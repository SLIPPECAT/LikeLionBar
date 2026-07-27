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
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
