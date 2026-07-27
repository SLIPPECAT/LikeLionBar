import AppKit
import SwiftUI
import LikeLionBarCore

/// 설정 창의 편집 상태.
///
/// 시각은 문자열로 들고 있다가 저장할 때 한 번에 검증한다.
/// 타이핑 도중에 값이 튀거나 지워지면 입력이 불쾌해진다.
final class SettingsModel: ObservableObject {
    @Published var courseSlug = ""
    @Published var chromeProfile = ""

    @Published var checkInWindowStart = ""
    @Published var lateDeadline = ""
    @Published var classroomAvailableFrom = ""
    @Published var classStart = ""
    @Published var classEnd = ""
    @Published var checkOutRemindFrom = ""

    @Published var checkInReminders = ""
    @Published var classroomReminder = ""
    @Published var checkOutReminders = ""
    @Published var cameraInterval = ""
    @Published var lunchStart = ""
    @Published var lunchEnd = ""

    @Published var launchAtLogin = false
    @Published var problem: String?
    @Published var savedAt: Date?

    init() { load() }

    func load() {
        let s = Settings.schedule
        courseSlug = Settings.courseSlug
        chromeProfile = Settings.chromeProfile

        checkInWindowStart = s.checkInWindowStart.text
        lateDeadline = s.lateDeadline.text
        classroomAvailableFrom = s.classroomAvailableFrom.text
        classStart = s.classStart.text
        classEnd = s.classEnd.text
        checkOutRemindFrom = s.checkOutRemindFrom.text

        checkInReminders = HM.text(from: s.checkInReminders)
        classroomReminder = s.classroomReminder.text
        checkOutReminders = HM.text(from: s.checkOutReminders)
        cameraInterval = String(s.cameraIntervalMinutes)
        lunchStart = s.lunchStart.text
        lunchEnd = s.lunchEnd.text

        launchAtLogin = LoginItem.isEnabled
        problem = nil
    }

    func restoreDefaults() {
        Settings.resetSchedule()
        load()
        Settings.notifyChanged()
        savedAt = Date()
    }

    func save() {
        // 하나라도 형식이 깨졌으면 어느 칸인지 알려주고 전부 보류한다.
        // 일부만 저장되면 어떤 상태인지 알 수 없어진다.
        let fields: [(String, String)] = [
            ("카운트다운 시작", checkInWindowStart),
            ("지각 마감", lateDeadline),
            ("강의실 활성화", classroomAvailableFrom),
            ("수업 시작", classStart),
            ("수업 종료", classEnd),
            ("퇴실 표시 시작", checkOutRemindFrom),
            ("강의실 알림", classroomReminder),
            ("점심 시작", lunchStart),
            ("점심 종료", lunchEnd),
        ]
        for (label, value) in fields where HM(text: value) == nil {
            problem = "\(label)의 형식이 올바르지 않습니다 — 08:47 처럼 입력하세요"
            return
        }
        guard !HM.list(from: checkInReminders).isEmpty else {
            problem = "입실 알림을 최소 하나는 남겨두세요"
            return
        }
        guard !HM.list(from: checkOutReminders).isEmpty else {
            problem = "퇴실 알림을 최소 하나는 남겨두세요"
            return
        }
        guard let interval = Int(cameraInterval.trimmingCharacters(in: .whitespaces)), interval >= 0 else {
            problem = "카메라 간격은 0 이상의 숫자여야 합니다 (0이면 끔)"
            return
        }

        Settings.courseSlug = courseSlug.trimmingCharacters(in: .whitespaces)
        Settings.chromeProfile = chromeProfile.trimmingCharacters(in: .whitespaces)
        Settings.schedule = Schedule(
            checkInWindowStart: HM(text: checkInWindowStart)!,
            lateDeadline: HM(text: lateDeadline)!,
            classStart: HM(text: classStart)!,
            classEnd: HM(text: classEnd)!,
            classroomAvailableFrom: HM(text: classroomAvailableFrom)!,
            checkOutRemindFrom: HM(text: checkOutRemindFrom)!,
            checkInReminders: HM.list(from: checkInReminders),
            classroomReminder: HM(text: classroomReminder)!,
            checkOutReminders: HM.list(from: checkOutReminders),
            cameraIntervalMinutes: interval,
            lunchStart: HM(text: lunchStart)!,
            lunchEnd: HM(text: lunchEnd)!
        )

        if launchAtLogin != LoginItem.isEnabled, !LoginItem.set(launchAtLogin) {
            problem = "로그인 항목 등록에 실패했습니다. 앱을 /Applications 로 옮긴 뒤 다시 시도하세요."
            launchAtLogin = LoginItem.isEnabled
        } else {
            problem = nil
        }

        savedAt = Date()
        Settings.notifyChanged()
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("과정") {
                    field("과정 주소", $model.courseSlug, prompt: "kdt-cld-6th")
                    field("Chrome 프로필", $model.chromeProfile, prompt: "비우면 기본 프로필")
                    Text("강의보드 주소는 bootcamp.likelion.net/my/courses/detail/**과정주소**/board 로 만들어집니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("메뉴바 표시") {
                    time("카운트다운 시작", $model.checkInWindowStart)
                    time("지각 마감", $model.lateDeadline)
                    time("강의실 버튼 활성화", $model.classroomAvailableFrom)
                    time("수업 시작", $model.classStart)
                    time("수업 종료", $model.classEnd)
                    time("퇴실 표시 시작", $model.checkOutRemindFrom)
                }

                Section("알림") {
                    field("입실 알림", $model.checkInReminders, prompt: "08:47, 08:56")
                    time("강의실 알림", $model.classroomReminder)
                    field("퇴실 알림", $model.checkOutReminders, prompt: "17:57, 18:05")
                    field("카메라 확인 간격(분)", $model.cameraInterval, prompt: "40", width: 90)
                    time("점심 시작", $model.lunchStart)
                    time("점심 종료", $model.lunchEnd)
                    Text("여러 개는 쉼표로 구분합니다. 카메라 간격을 0으로 두면 알림을 끕니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("로그인 시 자동 시작", isOn: $model.launchAtLogin)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("기본값 복원") { model.restoreDefaults() }
                Spacer()
                if let problem = model.problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else if let savedAt = model.savedAt {
                    Text("저장됨 \(savedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("저장") { model.save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 480, height: 700)
    }

    private func time(_ label: String, _ binding: Binding<String>) -> some View {
        field(label, binding, prompt: "08:47", width: 90)
    }

    /// `TextField`의 첫 인자는 플레이스홀더가 아니라 레이블이라 Form에서 그대로 보인다.
    /// 힌트는 `prompt:`로 주고 레이블은 `LabeledContent`가 담당하게 한다.
    private func field(
        _ label: String,
        _ binding: Binding<String>,
        prompt: String,
        width: CGFloat? = nil
    ) -> some View {
        LabeledContent(label) {
            TextField("", text: binding, prompt: Text(prompt))
                .labelsHidden()
                .multilineTextAlignment(width == nil ? .leading : .trailing)
                .frame(width: width)
        }
    }
}

/// 설정 창을 하나만 띄우고 재사용한다.
final class SettingsWindowController {
    private var window: NSWindow?
    private let model = SettingsModel()

    func show() {
        if let window {
            model.load()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "LikeLionBar 설정"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
