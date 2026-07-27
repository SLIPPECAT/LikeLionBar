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

        button.image = faceImage(p.face, tone: p.tone, tint: tint)
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

    // MARK: - 사자 얼굴

    /// 매 틱마다 새로 그리면 낭비다. 얼굴×색조 조합은 몇 개 안 되므로 그대로 캐싱한다.
    private var faceCache: [String: NSImage] = [:]

    private static let faceSide: CGFloat = 18

    private func faceImage(_ face: Face, tone: BarPresentation.Tone, tint: NSColor?) -> NSImage? {
        let key = "\(face.rawValue)-\(tone)"
        if let cached = faceCache[key] { return cached }

        guard let url = Bundle.main.url(forResource: "lion_\(face.rawValue)", withExtension: "png"),
              let original = NSImage(contentsOf: url) else {
            Log.write("얼굴 이미지 없음 — lion_\(face.rawValue).png")
            return nil
        }

        let side = Self.faceSide
        let box = NSRect(x: 0, y: 0, width: side, height: side)

        let result = NSImage(size: NSSize(width: side, height: side))
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        original.draw(in: box)
        if let tint {
            // 선화의 불투명한 부분만 상태색으로 덮는다.
            tint.set()
            box.fill(using: .sourceAtop)
        }
        result.unlockFocus()

        // 색을 입히지 않은 경우에만 템플릿으로 두어 메뉴바 명암에 맡긴다.
        result.isTemplate = (tint == nil)

        faceCache[key] = result
        return result
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
