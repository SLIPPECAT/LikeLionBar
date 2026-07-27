import AppKit
import UserNotifications
import LikeLionBarCore

/// 알림을 띄우고 알림에서 온 버튼 클릭을 처리한다.
///
/// 메뉴바 표시가 1차 방어선이고 알림은 자리를 비웠을 때를 위한 보조다.
/// 그래서 조용히 실패해도 앱의 핵심 기능은 살아 있어야 한다.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    /// 설정이 바뀌면 갈아끼운다.
    var engine: ReminderEngine
    private let nowProvider: () -> Date
    private let stateProvider: () -> DayState

    private let onComplete: (Step) -> Void
    private let onOpenBoard: () -> Void

    private var isAuthorized = false
    private var lastTick: Date?
    private var cameraSnoozedUntil: Date?

    /// 이보다 오래 끊겼으면(맥이 자고 있었다면) 밀린 알림을 한꺼번에 쏟지 않는다.
    private let catchUpLimit: TimeInterval = 5 * 60

    private enum Category {
        static let step = "STEP"
        static let camera = "CAMERA"
    }

    private enum Action {
        static let done = "MARK_DONE"
        static let openBoard = "OPEN_BOARD"
        static let snooze = "SNOOZE_CAMERA"
    }

    init(
        engine: ReminderEngine,
        nowProvider: @escaping () -> Date,
        stateProvider: @escaping () -> DayState,
        onComplete: @escaping (Step) -> Void,
        onOpenBoard: @escaping () -> Void
    ) {
        self.engine = engine
        self.nowProvider = nowProvider
        self.stateProvider = stateProvider
        self.onComplete = onComplete
        self.onOpenBoard = onOpenBoard
        super.init()
    }

    func start() {
        Log.write("Notifier.start — bundleID=\(Bundle.main.bundleIdentifier ?? "없음")")
        center.delegate = self
        registerCategories()

        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error {
                Log.write("알림 권한 요청 실패 — \(error.localizedDescription)")
            }
            Log.write("알림 권한 granted=\(granted)")
            DispatchQueue.main.async { self?.isAuthorized = granted }
        }

        center.getNotificationSettings { settings in
            Log.write("알림 설정 status=\(settings.authorizationStatus.rawValue) alert=\(settings.alertSetting.rawValue)")
        }
    }

    private func registerCategories() {
        let done = UNNotificationAction(
            identifier: Action.done, title: "완료로 표시", options: []
        )
        let open = UNNotificationAction(
            identifier: Action.openBoard, title: "강의보드 열기", options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: Action.snooze, title: "30분 뒤에", options: []
        )

        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Category.step,
                actions: [open, done],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: Category.camera,
                actions: [done, snooze],
                intentIdentifiers: [],
                options: []
            ),
        ])
    }

    // MARK: - 틱

    func tick() {
        let now = nowProvider()
        defer { lastTick = now }

        // 첫 틱은 기준점만 잡는다. 실행하자마자 지난 알림이 쏟아지면 안 된다.
        guard let last = lastTick else { return }
        guard isAuthorized else { return }

        var due = engine.due(from: last, to: now, state: stateProvider())
        guard !due.isEmpty else { return }

        // 맥이 자고 있었다면 밀린 게 여러 개다. 종류별로 마지막 것만 남긴다.
        if now.timeIntervalSince(last) > catchUpLimit {
            due = lastPerStep(due)
        }

        for reminder in due {
            if case .camera = reminder, let until = cameraSnoozedUntil, now < until { continue }
            deliver(reminder)
        }
    }

    private func lastPerStep(_ reminders: [Reminder]) -> [Reminder] {
        var seen: [Step: Reminder] = [:]
        for reminder in reminders { seen[reminder.step] = reminder }
        return Step.allCases.compactMap { seen[$0] }
    }

    private func deliver(_ reminder: Reminder) {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.categoryIdentifier = reminder.step == .camera ? Category.camera : Category.step
        content.userInfo = ["step": reminder.step.rawValue]
        if reminder.isNoisy {
            content.sound = .default
        }

        // 같은 단계의 이전 알림은 밀어내고 하나만 남긴다.
        content.threadIdentifier = reminder.step.rawValue

        let request = UNNotificationRequest(
            identifier: "\(reminder.step.rawValue)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil  // 즉시
        )
        Log.write("알림 전달 시도 — \(reminder.title)")
        center.add(request) { error in
            if let error {
                Log.write("알림 전달 실패 — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 알림에서 온 반응

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 메뉴바 앱은 항상 "실행 중"이라 이걸 안 주면 배너가 안 뜬다.
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let raw = response.notification.request.content.userInfo["step"] as? String
        let step = raw.flatMap(Step.init(rawValue:))

        switch response.actionIdentifier {
        case Action.done:
            if let step { DispatchQueue.main.async { self.onComplete(step) } }
        case Action.openBoard, UNNotificationDefaultActionIdentifier:
            DispatchQueue.main.async { self.onOpenBoard() }
        case Action.snooze:
            cameraSnoozedUntil = nowProvider().addingTimeInterval(30 * 60)
        default:
            break
        }
        completionHandler()
    }
}
