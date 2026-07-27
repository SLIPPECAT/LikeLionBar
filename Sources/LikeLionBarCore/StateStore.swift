import Foundation

/// 오늘 상태를 디스크에 유지하고, 날짜가 바뀌면 리셋한다.
///
/// - `state.json` : 오늘 진행 상황. 앱을 껐다 켜도 유지된다.
/// - `log.jsonl`  : 전체 이력. 누적 추적과 "이번 주 기록"의 근거.
public final class StateStore {
    public private(set) var state: DayState

    private let directory: URL
    private let calendar: Calendar

    public init(directory: URL? = nil, calendar: Calendar = .current, now: Date = Date()) {
        self.directory = directory ?? Self.defaultDirectory
        self.calendar = calendar

        try? FileManager.default.createDirectory(
            at: self.directory, withIntermediateDirectories: true
        )

        let loaded = Self.load(from: self.directory.appendingPathComponent("state.json"))
        if let loaded, Self.isSameDay(loaded.day, as: now, calendar: calendar) {
            self.state = loaded
        } else {
            // 어제 것이거나 없으면 새로 시작한다.
            self.state = DayState.empty(for: now, calendar: calendar)
            save()
        }
    }

    public static var defaultDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LikeLionBar", isDirectory: true)
    }

    private var stateURL: URL { directory.appendingPathComponent("state.json") }
    private var logURL: URL { directory.appendingPathComponent("log.jsonl") }

    // MARK: - 변경

    /// 날짜가 넘어갔으면 새 하루로 리셋한다. 매 틱마다 호출해도 싸다.
    /// 자정을 넘겨 켜둔 채로 다음날을 맞는 경우를 잡는다.
    @discardableResult
    public func rollOverIfNeeded(now: Date) -> Bool {
        guard !Self.isSameDay(state.day, as: now, calendar: calendar) else { return false }
        state = DayState.empty(for: now, calendar: calendar)
        save()
        return true
    }

    public func toggle(_ step: Step, at date: Date) {
        if state.isDone(step) {
            state.uncomplete(step)
            append(step: step.rawValue, action: "uncompleted", at: date)
        } else {
            state.complete(step, at: date)
            append(step: step.rawValue, action: "completed", at: date)
        }
        save()
    }

    public func complete(_ step: Step, at date: Date) {
        guard !state.isDone(step) else { return }
        state.complete(step, at: date)
        append(step: step.rawValue, action: "completed", at: date)
        save()
    }

    public func setDayOff(_ isDayOff: Bool, at date: Date) {
        guard state.isDayOff != isDayOff else { return }
        state.isDayOff = isDayOff
        append(step: "-", action: isDayOff ? "dayOff" : "dayOn", at: date)
        save()
    }

    // MARK: - 입출력

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        // 원자적 쓰기. 저장 중 앱이 죽어도 파일이 깨지지 않는다.
        try? data.write(to: stateURL, options: .atomic)
    }

    private static func load(from url: URL) -> DayState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DayState.self, from: data)
    }

    private func append(step: String, action: String, at date: Date) {
        let day = String(
            format: "%04d-%02d-%02d",
            state.day.year ?? 0, state.day.month ?? 0, state.day.day ?? 0
        )
        let entry = LogEntry(timestamp: date, day: day, step: step, action: action)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard var line = try? encoder.encode(entry) else { return }
        line.append(0x0A)  // \n

        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: logURL, options: .atomic)
        }
    }

    // MARK: - 도우미

    private static func isSameDay(_ components: DateComponents, as date: Date, calendar: Calendar) -> Bool {
        let today = calendar.dateComponents([.year, .month, .day], from: date)
        return components.year == today.year
            && components.month == today.month
            && components.day == today.day
    }
}

/// `log.jsonl`의 한 줄.
public struct LogEntry: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let day: String
    public let step: String
    public let action: String
}
