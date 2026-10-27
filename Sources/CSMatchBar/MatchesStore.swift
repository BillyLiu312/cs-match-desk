import AppKit
import Combine
import Foundation

@MainActor
final class MatchesStore: ObservableObject {
    struct EventGroup: Identifiable {
        let event: String
        let matches: [Match]

        var id: String { event.lowercased() }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case featured
        case all

        var id: String { rawValue }
        var title: String { self == .featured ? "焦点" : "全部" }
    }

    enum DaySelection: Int, CaseIterable, Identifiable {
        case yesterday = -1
        case today = 0
        case tomorrow = 1

        var id: Int { rawValue }

    }

    @Published private(set) var matches: [Match] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published var filter: Filter = .featured
    @Published var selectedDay: DaySelection = .today

    private let scraper = HLTVScraper()
    private var refreshTask: Task<Void, Never>?
    private var hasStarted = false
    private let refreshInterval: Duration = .seconds(300)
    private let cacheKey = "cachedMatches.v1"
    private let cacheDateKey = "cachedMatchesDate.v1"

    init() {
        restoreCache()
    }

    var visibleMatches: [Match] {
        let selectedMatches = matches.forDay(selectedDate).chronological()
        switch filter {
        case .featured:
            return selectedMatches.featuredSchedule()
        case .all:
            return selectedMatches.remainingSchedule()
        }
    }

    var selectedDate: Date {
        date(for: selectedDay)
    }

    var visibleGroups: [EventGroup] {
        Dictionary(grouping: visibleMatches, by: \.event)
            .map { event, matches in
                EventGroup(event: event, matches: matches.chronological())
            }
            .sorted { lhs, rhs in
                guard let left = lhs.matches.first, let right = rhs.matches.first else {
                    return lhs.event < rhs.event
                }
                if left.startsAt != right.startsAt { return left.startsAt < right.startsAt }
                return lhs.event < rhs.event
            }
    }

    var liveCount: Int {
        matches.forToday().filter { $0.status == .live }.count
    }

    func resetToToday() {
        selectedDay = .today
    }

    func date(for day: DaySelection) -> Date {
        Calendar.current.date(byAdding: .day, value: day.rawValue, to: Date()) ?? Date()
    }

    func dayTitle(for day: DaySelection) -> String {
        guard day != .today else { return "今天" }
        let weekday = Calendar.current.component(.weekday, from: date(for: day))
        let titles = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return titles[max(0, min(weekday - 1, titles.count - 1))]
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: self.refreshInterval)
                if Task.isCancelled { return }
                await self.refresh()
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        do {
            let freshMatches = try await scraper.fetchMatches()
            var merged = Dictionary(uniqueKeysWithValues: freshMatches.map { ($0.id, $0) })
            let calendar = Calendar.current
            let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            for match in matches where match.status == .completed
                && (calendar.isDateInToday(match.startsAt) || calendar.isDate(match.startsAt, inSameDayAs: yesterday)) {
                if merged[match.id] == nil {
                    merged[match.id] = match
                }
            }
            matches = Array(merged.values).chronological()
            lastUpdated = Date()
            saveCache()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func open(_ match: Match) {
        NSWorkspace.shared.open(match.url)
    }

    func openHLTV() {
        guard let url = URL(string: "https://www.hltv.org/matches") else { return }
        NSWorkspace.shared.open(url)
    }

    private func saveCache() {
        guard let data = try? JSONEncoder.hltv.encode(matches) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(lastUpdated, forKey: cacheDateKey)
    }

    private func restoreCache() {
        guard
            let data = UserDefaults.standard.data(forKey: cacheKey),
            let cached = try? JSONDecoder.hltv.decode([Match].self, from: data)
        else { return }
        matches = cached
        lastUpdated = UserDefaults.standard.object(forKey: cacheDateKey) as? Date
    }
}

private extension JSONEncoder {
    static var hltv: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var hltv: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
