import AppKit
import SwiftUI
import LikeLionBarCore

/// 편집 중인 커스텀 알림 한 줄.
///
/// 시각을 문자열로 들고 있다가 저장할 때 한 번에 검증한다.
/// 타이핑 도중에 값이 튀면 입력이 불쾌해진다.
struct EditableReminder: Identifiable, Equatable {
    var id: UUID
    var timeText: String
    var title: String
    var isDaily: Bool
    /// 일회성일 때 원래 날짜. 편집해도 그대로 이어간다.
    var day: DateComponents?

    init(from reminder: CustomReminder) {
        id = reminder.id
        timeText = reminder.time.text
        title = reminder.title
        isDaily = reminder.isDaily
        day = reminder.day
    }

    /// 새로 추가하는 항목은 오늘 하루짜리로 시작한다.
    init(newOn date: Date, calendar: Calendar) {
        id = UUID()
        timeText = ""
        title = ""
        isDaily = false
        day = calendar.dateComponents([.year, .month, .day], from: date)
    }
}

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
    @Published var photoDeadlineMinute = ""
    @Published var photoReminderMinutes = ""
    @Published var lunchStart = ""
    @Published var lunchEnd = ""

    @Published var notificationSound = false
    @Published var launchAtLogin = false
    @Published var customReminders: [EditableReminder] = []
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
        photoDeadlineMinute = String(s.photoDeadlineMinute)
        photoReminderMinutes = s.photoReminderMinutes.map(String.init).joined(separator: ", ")
        lunchStart = s.lunchStart.text
        lunchEnd = s.lunchEnd.text

        notificationSound = Settings.notificationSound
        launchAtLogin = LoginItem.isEnabled

        // 지난 일회성 알림은 목록에서 치우고 보여준다.
        Settings.pruneExpiredReminders()
        customReminders = Settings.customReminders.map(EditableReminder.init(from:))

        problem = nil
    }

    func addReminder() {
        customReminders.append(EditableReminder(newOn: Date(), calendar: .current))
    }

    func removeReminder(_ id: UUID) {
        customReminders.removeAll { $0.id == id }
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
        guard let deadline = Int(photoDeadlineMinute.trimmingCharacters(in: .whitespaces)),
              (0..<60).contains(deadline) else {
            problem = "사진 마감은 0~59 사이의 분이어야 합니다 (0이면 끔)"
            return
        }
        let photoMinutes = photoReminderMinutes.split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { (0..<60).contains($0) }
        guard !photoMinutes.isEmpty else {
            problem = "사진 알림을 최소 하나는 남겨두세요 (예: 2, 12)"
            return
        }
        guard photoMinutes.allSatisfy({ $0 < deadline }) else {
            problem = "사진 알림은 마감(\(deadline)분)보다 앞이어야 합니다"
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
            photoDeadlineMinute: deadline,
            photoReminderMinutes: photoMinutes,
            lunchStart: HM(text: lunchStart)!,
            lunchEnd: HM(text: lunchEnd)!
        )
        Settings.notificationSound = notificationSound

        // 빈 줄은 추가만 하고 안 채운 것이니 조용히 버린다.
        let filled = customReminders.filter {
            !$0.timeText.trimmingCharacters(in: .whitespaces).isEmpty
                || !$0.title.trimmingCharacters(in: .whitespaces).isEmpty
        }
        for item in filled where HM(text: item.timeText) == nil {
            problem = "내 알림의 시각 형식이 올바르지 않습니다 — 13:40 처럼 입력하세요"
            return
        }
        for item in filled where item.title.trimmingCharacters(in: .whitespaces).isEmpty {
            problem = "내 알림에 내용을 적어주세요 (\(item.timeText))"
            return
        }
        Settings.customReminders = filled.map { item in
            CustomReminder(
                id: item.id,
                time: HM(text: item.timeText)!,
                title: item.title.trimmingCharacters(in: .whitespaces),
                isDaily: item.isDaily,
                day: item.isDaily ? nil : item.day
            )
        }
        customReminders = filled

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
                    Toggle("알림에 소리 사용", isOn: $model.notificationSound)
                    Text("여러 개는 쉼표로 구분합니다. 소리를 끄면 배너만 뜹니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("매시간 사진") {
                    field("마감 (정각 기준 분)", $model.photoDeadlineMinute, prompt: "20", width: 90)
                    field("알림 (정각 기준 분)", $model.photoReminderMinutes, prompt: "2, 12", width: 90)
                    time("점심 시작", $model.lunchStart)
                    time("점심 종료", $model.lunchEnd)
                    Text("매시 정각부터 마감까지 사진을 찍습니다. 점심 시간대는 건너뜁니다. 마감을 0으로 두면 끕니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("내 알림") {
                    if model.customReminders.isEmpty {
                        Text("등록된 알림이 없습니다. 병원·외출 같은 개인 일정을 넣어보세요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach($model.customReminders) { $item in
                        HStack(spacing: 8) {
                            TextField("", text: $item.timeText, prompt: Text("13:40"))
                                .labelsHidden()
                                .multilineTextAlignment(.center)
                                .frame(width: 64)
                            TextField("", text: $item.title, prompt: Text("병원"))
                                .labelsHidden()
                            Toggle("매 평일", isOn: $item.isDaily)
                                .toggleStyle(.checkbox)
                                .fixedSize()
                            Button {
                                model.removeReminder(item.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("삭제")
                        }
                    }
                    Button("알림 추가") { model.addReminder() }
                    Text("`매 평일`을 끄면 오늘 하루만 울리고 다음 날 목록에서 사라집니다.")
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
        // 항목이 많아 화면 높이를 넘긴다. 창을 늘릴 수 있어야 스크롤 없이 볼 수 있다.
        .frame(minWidth: 520, idealWidth: 520, minHeight: 420, idealHeight: 680)
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
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 680))
        window.center()

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
