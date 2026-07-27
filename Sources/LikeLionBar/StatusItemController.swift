import AppKit
import LikeLionBarCore

/// `BarPresentation`을 실제 메뉴바 아이템으로 그린다.
final class StatusItemController {
    private let statusItem: NSStatusItem
    /// 설정이 바뀌면 갈아끼운다.
    var engine: ScheduleEngine
    private let nowProvider: () -> Date
    private let stateProvider: () -> DayState

    private var tickTimer: Timer?
    private var blinkTimer: Timer?
    private var blinkVisible = true
    private var current: BarPresentation?

    /// 매 틱마다 함께 돌려야 하는 것들 (알림 등).
    var onTick: (() -> Void)?

    init(
        engine: ScheduleEngine,
        nowProvider: @escaping () -> Date,
        stateProvider: @escaping () -> DayState
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.engine = engine
        self.nowProvider = nowProvider
        self.stateProvider = stateProvider
    }

    var menu: NSMenu? {
        get { statusItem.menu }
        set { statusItem.menu = newValue }
    }

    func start() {
        refresh()

        // 카운트다운의 초가 실제로 줄어드는 게 보여야 다급함이 전달된다.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.refresh() }
        // 메뉴를 열어둔 동안에도 계속 돌아야 한다.
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer

        // 맥을 덮었다 열면 타이머가 밀려 있을 수 있으니 즉시 맞춘다.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleWake() {
        refresh()
    }

    func refresh() {
        onTick?()

        let presentation = engine.presentation(now: nowProvider(), state: stateProvider())
        guard presentation != current else { return }

        if presentation.blinking != (current?.blinking ?? false) {
            setBlinking(presentation.blinking)
        }
        current = presentation
        render()
    }

    // MARK: - 그리기

    private func render() {
        guard let button = statusItem.button, let p = current else { return }

        let tint = color(for: p.tone)

        // 메뉴바는 템플릿 이미지를 시스템 색으로 강제 렌더링하므로 contentTintColor가 무시된다.
        // 색을 넣으려면 심볼 자체에 구워야 한다. quiet일 때만 템플릿으로 두어 명암에 맡긴다.
        var config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        if let tint {
            config = config.applying(NSImage.SymbolConfiguration(hierarchicalColor: tint))
        }
        let image = NSImage(systemSymbolName: p.symbol, accessibilityDescription: p.text)?
            .withSymbolConfiguration(config)
        image?.isTemplate = (tint == nil)
        button.image = image
        button.contentTintColor = nil

        if let text = p.text {
            button.imagePosition = .imageLeft
            button.attributedTitle = NSAttributedString(
                string: " " + text,
                attributes: [
                    .foregroundColor: tint ?? NSColor.labelColor,
                    // 고정폭 숫자가 아니면 초가 바뀔 때마다 폭이 흔들려 거슬린다.
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                ]
            )
        } else {
            button.imagePosition = .imageOnly
            button.attributedTitle = NSAttributedString(string: "")
        }

        button.alphaValue = (p.blinking && !blinkVisible) ? 0.25 : 1.0
    }

    private func color(for tone: BarPresentation.Tone) -> NSColor? {
        switch tone {
        case .quiet:   return nil          // 템플릿 이미지가 알아서 맞춘다
        case .done:    return .systemGreen
        case .warning: return .systemOrange
        case .alert:   return .systemRed
        }
    }

    // MARK: - 깜빡임

    private func setBlinking(_ on: Bool) {
        blinkTimer?.invalidate()
        blinkTimer = nil
        blinkVisible = true

        guard on else {
            statusItem.button?.alphaValue = 1.0
            return
        }

        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.blinkVisible.toggle()
            self.statusItem.button?.alphaValue = self.blinkVisible ? 1.0 : 0.25
        }
        RunLoop.main.add(timer, forMode: .common)
        blinkTimer = timer
    }

    deinit {
        tickTimer?.invalidate()
        blinkTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
