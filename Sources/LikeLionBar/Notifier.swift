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
    private var lastRealTick: Date?

    /// LIKELIONBAR_TRACE=1 이면 매 틱의 검사 구간을 남긴다. 알림이 왜 안 떴는지 볼 때 쓴다.
    private let trace = ProcessInfo.processInfo.environment["LIKELIONBAR_TRACE"] != nil
    private lazy var traceFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// 이보다 오래 끊겼으면(맥이 자고 있었다면) 밀린 알림을 한꺼번에 쏟지 않는다.
    private let catchUpLimit: TimeInterval = 5 * 60

    private enum Category {
        static let step = "STEP"
        static let camera = "CAMERA"
        static let plain = "PLAIN"
    }

    private enum Action {
        static let done = "MARK_DONE"
        static let openBoard = "OPEN_BOARD"
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
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Category.step,
                actions: [open, done],
                intentIdentifiers: [],
                options: []
            ),
            // 사진은 강의보드와 무관하고, 마감이 :20이라 미루기도 의미가 없다.
            UNNotificationCategory(
                identifier: Category.camera,
                actions: [done],
                intentIdentifiers: [],
                options: []
            ),
            // 커스텀 알림은 알려주는 게 전부다.
            UNNotificationCategory(
                identifier: Category.plain,
                actions: [],
                intentIdentifiers: [],
                options: []
            ),
        ])
    }

    // MARK: - 틱

    func tick() {
        let now = nowProvider()
        let realNow = Date()
        defer { lastTick = now; lastRealTick = realNow }

        // 틱이 1초마다 안 돌면 카운트다운이 멈추고 알림이 밀린다. 조용히 어긋나면
        // 원인을 찾기 어려우므로 눈에 띄게 남긴다.
        if let lastReal = lastRealTick, realNow.timeIntervalSince(lastReal) > 3 {
            Log.write("틱이 \(Int(realNow.timeIntervalSince(lastReal)))초 만에 돌았다 — 절전/슬립 의심")
        }

        // 첫 틱은 기준점만 잡는다. 실행하자마자 지난 알림이 쏟아지면 안 된다.
        guard let last = lastTick else { return }
        guard isAuthorized else { return }

        let state = stateProvider()
        var due = engine.due(from: last, to: now, state: state)

        if trace {
            Log.write("틱 \(traceFormatter.string(from: last)) → \(traceFormatter.string(from: now))"
                + "  due=\(due.count)  checkIn완료=\(state.isDone(.checkIn))")
        }

        guard !due.isEmpty else { return }

        // 맥이 자고 있었다면 밀린 게 여러 개다. 종류별로 마지막 것만 남긴다.
        if now.timeIntervalSince(last) > catchUpLimit {
            due = lastPerStep(due)
        }

        for reminder in due {
            deliver(reminder)
        }
    }

    private func lastPerStep(_ reminders: [Reminder]) -> [Reminder] {
        var seen: [Step: Reminder] = [:]
        // 커스텀 알림은 각자 다른 일정이라 하나로 합치면 안 된다. 전부 남긴다.
        var customs: [Reminder] = []
        for reminder in reminders {
            if let step = reminder.step { seen[step] = reminder } else { customs.append(reminder) }
        }
        return Step.allCases.compactMap { seen[$0] } + customs
    }

    private func deliver(_ reminder: Reminder) {
        let step = reminder.step

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body(deadlineMinute: engine.schedule.photoDeadlineMinute)
        content.categoryIdentifier = category(for: step)
        content.userInfo = ["step": step?.rawValue ?? ""]
        // 기본은 팝업만. 소리는 설정에서 켠 사람만 받는다.
        if Settings.notificationSound {
            content.sound = .default
        }

        // 같은 단계의 이전 알림은 밀어내고 하나만 남긴다.
        // 커스텀은 서로 다른 일정이므로 묶지 않는다.
        let thread = step?.rawValue ?? "custom-\(reminder.title)"
        content.threadIdentifier = thread

        let request = UNNotificationRequest(
            identifier: "\(thread)-\(Date().timeIntervalSince1970)",
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

    /// 커스텀 알림은 완료 표시할 것도, 열 강의보드도 없다. 버튼 없이 띄운다.
    private func category(for step: Step?) -> String {
        switch step {
        case .camera: return Category.camera
        case .none:   return Category.plain
        default:      return Category.step
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
        Log.write("알림 응답 — action=\(response.actionIdentifier) step=\(raw ?? "없음")")

        switch response.actionIdentifier {
        case Action.done:
            if let step { DispatchQueue.main.async { self.onComplete(step) } }
        case Action.openBoard, UNNotificationDefaultActionIdentifier:
            // 사진 알림은 강의보드와 무관하니 배너를 눌러도 브라우저를 열지 않는다.
            guard step != .camera else { break }
            DispatchQueue.main.async { self.onOpenBoard() }
        default:
            break
        }
        completionHandler()
    }
}
