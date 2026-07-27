import Foundation
import ServiceManagement

/// 로그인 시 자동 시작.
///
/// 매일 아침 쓰는 앱이라 수동으로 켜야 한다면 존재 의미가 절반은 사라진다.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 성공 여부를 돌려준다. 실패 사유는 로그에 남긴다.
    ///
    /// 앱이 `~/Downloads`나 빌드 폴더처럼 임시 위치에 있으면 등록이 거부될 수 있다.
    /// `/Applications`로 옮긴 뒤 다시 시도해야 한다.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Log.write("로그인 항목 \(enabled ? "등록" : "해제") 성공")
            return true
        } catch {
            Log.write("로그인 항목 \(enabled ? "등록" : "해제") 실패 — \(error.localizedDescription)")
            return false
        }
    }
}
