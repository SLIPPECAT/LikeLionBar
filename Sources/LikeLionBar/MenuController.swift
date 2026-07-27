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
            header("쉬는 날로 표시됨", italic: true)
        }

        menu.addItem(.separator())

        for step in Step.allCases {
            menu.addItem(stepItem(step, state: state))
        }

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

    private func stepItem(_ step: Step, state: DayState) -> NSMenuItem {
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
        store.toggle(step, at: nowProvider())
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
