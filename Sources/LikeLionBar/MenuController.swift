import AppKit
import LikeLionBarCore

/// 드롭다운 메뉴를 만들고 클릭을 처리한다.
///
/// 메뉴가 열릴 때마다 다시 만든다. 상태가 계속 바뀌므로 미리 만들어두면 어긋난다.
final class MenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu()

    private let store: StateStore
    private let nowProvider: () -> Date
    /// 설정이 바뀌면 갈아끼운다.
    var launcher: Launcher
    var schedule: Schedule = .default
    var customReminders: [CustomReminder] = []
    private let calendar = Calendar.current
    private let onChange: () -> Void
    var onOpenSettings: (() -> Void)?

    private lazy var dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 (E)"
        return f
    }()

    private lazy var timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "HH:mm"
        return f
    }()

    init(
        store: StateStore,
        nowProvider: @escaping () -> Date,
        launcher: Launcher,
        onChange: @escaping () -> Void
    ) {
        self.store = store
        self.nowProvider = nowProvider
        self.launcher = launcher
        self.onChange = onChange
        super.init()
        menu.delegate = self
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    // MARK: - 구성

    private func rebuild() {
        menu.removeAllItems()

        let now = nowProvider()
        let state = store.state

        header("오늘 · \(dayFormatter.string(from: now))")

        if state.isDayOff {
            // 자동으로 켜진 거라면 왜 켜졌는지 알려줘야 되돌릴 판단을 할 수 있다.
            if let reason = state.autoDayOffReason {
                header("\(reason) — 공휴일이라 쉬는 날 처리됨", italic: true)
            } else {
                header("쉬는 날로 표시됨", italic: true)
            }
        }

        menu.addItem(.separator())

        for step in Step.allCases {
            menu.addItem(stepItem(step, state: state))
        }

        addCustomReminders(now: now, state: state)

        menu.addItem(.separator())

        // QR 입퇴실과 강의실 입장 버튼이 모두 강의보드 위에 있어 목적지가 하나다.
        // 항목을 셋으로 나누면 같은 동작이 세 번 보일 뿐이다.
        add("강의보드 열기  (QR·강의실 입장)", key: "1", action: #selector(openBoard))

        menu.addItem(.separator())

        let dayOffTitle = state.isDayOff ? "쉬는 날 표시 해제" : "오늘은 쉬는 날로 표시"
        add(dayOffTitle, key: "", action: #selector(toggleDayOff))
        add("기록 폴더 열기", key: "", action: #selector(openLogFolder))

        menu.addItem(.separator())

        if DebugClock.isActive {
            header("가짜 시각 모드", italic: true)
        }
        add("설정…", key: ",", action: #selector(openSettings))
        add("종료", key: "q", action: #selector(NSApplication.terminate(_:)), target: NSApp)
    }

    /// 오늘 울릴 내 알림들. 메뉴바에는 안 띄우기로 했으니 여기서만 보여준다.
    private func addCustomReminders(now: Date, state: DayState) {
        let today = customReminders
            .filter { $0.applies(to: now, isDayOff: state.isDayOff, calendar: calendar) }
            .sorted { $0.time < $1.time }
        guard !today.isEmpty else { return }

        menu.addItem(.separator())
        header("내 알림")

        let nowMinutes = calendar.component(.hour, from: now) * 60
            + calendar.component(.minute, from: now)

        for reminder in today {
            let passed = reminder.time.minutesSinceMidnight <= nowMinutes
            let item = NSMenuItem(
                title: "\(reminder.time.text)   \(reminder.title)",
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            // 이미 지난 건 흐리게 둬서 남은 것만 눈에 들어오게 한다.
            item.attributedTitle = NSAttributedString(
                string: "\(reminder.time.text)   \(reminder.title)",
                attributes: [
                    .foregroundColor: passed
                        ? NSColor.tertiaryLabelColor
                        : NSColor.labelColor,
                    .font: NSFont.menuFont(ofSize: 0),
                ]
            )
            menu.addItem(item)
        }
    }

    /// 사진은 하루 한 번이 아니라 시간마다라 따로 그린다.
    private func photoItem(state: DayState) -> NSMenuItem {
        let hour = calendar.component(.hour, from: nowProvider())
        let total = schedule.photoHours.count
        let done = state.donePhotoHours.count
        let tally = "오늘 \(done)/\(total)"

        guard schedule.photoHours.contains(hour) else {
            // 점심시간이거나 수업 시간 밖. 조를 일이 없다.
            let item = NSMenuItem(title: "⬜️  사진 — 지금은 해당 없음          \(tally)",
                                  action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }

        let isDone = state.isPhotoDone(hour: hour)
        let item = NSMenuItem(
            title: "\(isDone ? "✅" : "⬜️")  \(hour)시 사진          \(tally)",
            action: #selector(togglePhoto),
            keyEquivalent: ""
        )
        item.target = self
        item.toolTip = isDone
            ? "클릭하면 완료를 취소합니다"
            : String(format: "%d:%02d까지 찍고 클릭하세요", hour, schedule.photoDeadlineMinute)
        return item
    }

    private func stepItem(_ step: Step, state: DayState) -> NSMenuItem {
        if step == .camera { return photoItem(state: state) }

        let done = state.isDone(step)
        let mark = done ? "✅" : "⬜️"

        var title = "\(mark)  \(step.label)"
        if let at = state.completed[step] {
            title += "          \(timeFormatter.string(from: at))"
        }

        let item = NSMenuItem(title: title, action: #selector(toggleStep(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = step.rawValue
        item.toolTip = done ? "클릭하면 완료를 취소합니다" : "처리한 뒤 클릭해 완료로 표시하세요"
        return item
    }

    // MARK: - 메뉴 만들기 도우미

    private func header(_ text: String, italic: Bool = false) {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        let font = italic
            ? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            : NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        item.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        )
        menu.addItem(item)
    }

    @discardableResult
    private func add(_ title: String, key: String, action: Selector, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        menu.addItem(item)
        return item
    }

    // MARK: - 동작

    @objc private func toggleStep(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let step = Step(rawValue: raw) else {
            return
        }
        Log.write("메뉴에서 \(step.label) 토글 (사용자 클릭)")
        store.toggle(step, at: nowProvider())
        onChange()
    }

    @objc private func togglePhoto() {
        let now = nowProvider()
        let hour = calendar.component(.hour, from: now)
        Log.write("메뉴에서 \(hour)시 사진 토글 (사용자 클릭)")
        store.togglePhoto(hour: hour, at: now)
        onChange()
    }

    @objc private func toggleDayOff() {
        store.setDayOff(!store.state.isDayOff, at: nowProvider())
        onChange()
    }

    @objc private func openBoard() { launcher.openBoard() }

    @objc private func openLogFolder() {
        NSWorkspace.shared.open(StateStore.defaultDirectory)
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }
}
