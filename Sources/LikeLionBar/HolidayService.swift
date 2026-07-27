import Foundation
import LikeLionBarCore

/// 공휴일 목록을 받아와 캐시한다.
///
/// 네트워크가 없어도 앱의 본래 기능은 그대로 돌아야 하므로, 실패하면 조용히
/// 캐시를 쓰고 캐시도 없으면 공휴일 판단만 건너뛴다.
///
/// 보내는 정보는 연도와 국가 코드뿐이다. 사용자 데이터는 나가지 않는다.
final class HolidayService {
    /// 키가 필요 없는 공개 API. 응답에 개인정보가 포함되지 않는다.
    private static let endpoint = "https://date.nager.at/api/v3/PublicHolidays"

    private let calendar: Calendar
    private let directory: URL
    private var cached: HolidayCalendar?
    private var isFetching = false

    init(calendar: Calendar = .current, directory: URL = StateStore.defaultDirectory) {
        self.calendar = calendar
        self.directory = directory
        self.cached = Self.load(from: cacheURL(for: calendar.component(.year, from: Date())))
    }

    private func cacheURL(for year: Int) -> URL {
        directory.appendingPathComponent("holidays-\(year).json")
    }

    /// 이 날짜가 공휴일이면 이름을 돌려준다. 모르면 nil.
    func holiday(on date: Date) -> Holiday? {
        guard let cached, cached.covers(date, calendar: calendar) else { return nil }
        return cached.holiday(on: date, calendar: calendar)
    }

    /// 캐시가 없거나 오래됐으면 새로 받아온다.
    ///
    /// 공휴일은 1년에 몇 번 바뀌지 않지만 대체공휴일이 뒤늦게 지정되는 일이 있어
    /// 30일마다 다시 확인한다.
    func refreshIfNeeded(now: Date = Date(), completion: (() -> Void)? = nil) {
        guard Settings.useHolidayCalendar else { return }
        guard !isFetching else { return }

        let year = calendar.component(.year, from: now)
        if let cached, cached.year == year,
           now.timeIntervalSince(cached.fetchedAt) < 30 * 24 * 60 * 60 {
            return
        }

        guard let url = URL(string: "\(Self.endpoint)/\(year)/KR") else { return }
        isFetching = true

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            defer { self.isFetching = false }

            if let error {
                Log.write("공휴일 조회 실패 — \(error.localizedDescription)")
                return
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data else {
                Log.write("공휴일 조회 실패 — 응답이 올바르지 않다")
                return
            }

            struct Entry: Decodable {
                let date: String
                let localName: String
                let name: String
            }
            guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
                Log.write("공휴일 조회 실패 — 응답을 해석할 수 없다")
                return
            }

            let calendarData = HolidayCalendar(
                year: year,
                holidays: entries.map { Holiday(date: $0.date, name: $0.localName) }
            )
            self.save(calendarData, year: year)

            DispatchQueue.main.async {
                self.cached = calendarData
                Log.write("공휴일 \(entries.count)건 받아옴 (\(year)년)")
                completion?()
            }
        }.resume()
    }

    // MARK: - 캐시 입출력

    private func save(_ data: HolidayCalendar, year: Int) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let encoded = try? encoder.encode(data) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? encoded.write(to: cacheURL(for: year), options: .atomic)
    }

    private static func load(from url: URL) -> HolidayCalendar? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HolidayCalendar.self, from: data)
    }
}
