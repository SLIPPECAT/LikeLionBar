import AppKit
import LikeLionBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    private var menuController: MenuController?
    private var notifier: Notifier?
    private var store: StateStore?
    private let settingsWindow = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let nowProvider = DebugClock.makeNowProvider()

        // 미리보기 모드는 실제 기록을 건드리면 안 된다. 임시 폴더에 따로 쓴다.
        let store = StateStore(directory: DebugClock.previewDirectory, now: nowProvider())
        for step in DebugClock.fakeCompletedSteps() {
            store.complete(step, at: nowProvider())
        }
        self.store = store

        let statusController = StatusItemController(
            engine: ScheduleEngine(schedule: Settings.schedule),
            nowProvider: nowProvider,
            stateProvider: {
                // 자정을 넘겨 켜둔 채로 다음날을 맞는 경우를 여기서 잡는다.
                store.rollOverIfNeeded(now: nowProvider())
                return store.state
            }
        )

        let menuController = MenuController(
            store: store,
            nowProvider: nowProvider,
            launcher: makeLauncher(),
            onChange: { [weak statusController] in statusController?.refresh() }
        )
        menuController.onOpenSettings = { [weak self] in self?.settingsWindow.show() }

        let notifier = Notifier(
            engine: ReminderEngine(schedule: Settings.schedule),
            nowProvider: nowProvider,
            stateProvider: { store.state },
            onComplete: { [weak statusController] step in
                store.complete(step, at: nowProvider())
                statusController?.refresh()
            },
            onOpenBoard: { [weak menuController] in menuController?.launcher.openBoard() }
        )
        notifier.start()

        statusController.menu = menuController.menu
        statusController.onTick = { [weak notifier] in notifier?.tick() }
        statusController.start()

        self.statusController = statusController
        self.menuController = menuController
        self.notifier = notifier

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applySettings),
            name: Settings.didChange,
            object: nil
        )

        let profile = Settings.chromeProfile.isEmpty ? "기본" : Settings.chromeProfile
        Log.write("시작 — slug=\(Settings.courseSlug) profile=\(profile)")

        // 메뉴바 클릭을 자동화하기 어려워 설정 창 확인용 통로를 둔다.
        if ProcessInfo.processInfo.environment["LIKELIONBAR_OPEN_SETTINGS"] != nil {
            settingsWindow.show()
        }
    }

    private func makeLauncher() -> Launcher {
        Launcher(courseSlug: Settings.courseSlug, chromeProfile: Settings.chromeProfile)
    }

    /// 설정을 저장하면 엔진을 새 값으로 갈아끼운다. 앱을 다시 켤 필요가 없어야 한다.
    @objc private func applySettings() {
        let schedule = Settings.schedule
        statusController?.engine = ScheduleEngine(schedule: schedule)
        notifier?.engine = ReminderEngine(schedule: schedule)
        menuController?.launcher = makeLauncher()
        statusController?.refresh()
        Log.write("설정 적용됨")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
