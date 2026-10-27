import Foundation

struct Match: Codable, Identifiable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case upcoming
        case live
        case completed
    }

    let id: String
    let team1: String
    let team2: String
    let team1LogoURL: URL?
    let team2LogoURL: URL?
    let event: String
    let stage: String?
    let bestOf: String
    let startsAt: Date
    let status: Status
    let stars: Int
    let score1: String?
    let score2: String?
    let mapWins1: Int?
    let mapWins2: Int?
    let url: URL

    var isFeatured: Bool {
        stars >= 3
    }

    var hasScore: Bool {
        score1 != nil && score2 != nil
    }

    var mapsNeededToWin: Int? {
        let digits = bestOf.filter(\.isNumber)
        guard let bestOfCount = Int(digits), bestOfCount > 0 else { return nil }
        return (bestOfCount + 1) / 2
    }

    var displayedScore1: String? { displayedScore(score1) }
    var displayedScore2: String? { displayedScore(score2) }

    var seriesWins1: Int { resolvedSeriesWins(explicit: mapWins1, legacyScore: score1) }
    var seriesWins2: Int { resolvedSeriesWins(explicit: mapWins2, legacyScore: score2) }

    var isImportantEvent: Bool {
        Self.isImportantEventName(event)
    }

    static func isImportantEventName(_ event: String) -> Bool {
        let normalized = event.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let keywords = [
            "IEM", "INTEL EXTREME MASTERS", "PGL", "ESL", "BLAST",
            "EWC", "ESPORTS WORLD CUP", "CAC", "CS ASIA CHAMPIONSHIPS", "MAJOR"
        ]
        return keywords.contains { keyword in
            normalized.range(of: keyword, options: [.caseInsensitive]) != nil
        }
    }

    static func displayTeamName(_ name: String) -> String {
        let aliases = [
            "ninjas in pyjamas": "NIP",
            "natus vincere": "NAVI",
            "eternal fire": "Eternal",
            "the mongolz": "MGLZ",
            "100 thieves": "100T",
            "gamerlegion": "GL",
            "parivision": "PV",
            "virtus.pro": "VP"
        ]
        return aliases[name.lowercased()] ?? name
    }

    private func displayedScore(_ score: String?) -> String? {
        guard let score else { return nil }
        if status == .live, let parenthesis = score.firstIndex(of: "(") {
            return String(score[..<parenthesis]).trimmingCharacters(in: .whitespaces)
        }
        return score
    }

    private func resolvedSeriesWins(explicit: Int?, legacyScore: String?) -> Int {
        if let explicit { return max(0, explicit) }
        if status == .completed { return Int(legacyScore ?? "") ?? 0 }
        guard
            let legacyScore,
            let opening = legacyScore.firstIndex(of: "("),
            let closing = legacyScore[opening...].firstIndex(of: ")")
        else { return 0 }
        return Int(legacyScore[legacyScore.index(after: opening)..<closing]) ?? 0
    }
}

extension Array where Element == Match {
    func forToday(now: Date = Date(), calendar: Calendar = .current) -> [Match] {
        forDay(now, calendar: calendar)
    }

    func forDay(_ date: Date, calendar: Calendar = .current) -> [Match] {
        filter { calendar.isDate($0.startsAt, inSameDayAs: date) }
    }

    func chronological() -> [Match] {
        sorted { lhs, rhs in
            if lhs.startsAt != rhs.startsAt { return lhs.startsAt < rhs.startsAt }
            return lhs.id < rhs.id
        }
    }

    func featuredSchedule(minimumCount: Int = 4) -> [Match] {
        let ordered = chronological()
        let important = ordered.filter(\.isImportantEvent)
        return important.isEmpty ? Array(ordered.prefix(minimumCount)) : important
    }

    func remainingSchedule(minimumFeaturedCount: Int = 4) -> [Match] {
        let featuredIDs = Set(featuredSchedule(minimumCount: minimumFeaturedCount).map(\.id))
        return chronological().filter { !featuredIDs.contains($0.id) }
    }
}
