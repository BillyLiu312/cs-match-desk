import Foundation

@main
struct MatchChecks {
    static func main() throws {
        try todayKeepsLiveAndLocalDayMatches()
        try dayFilterSeparatesYesterdayTodayAndTomorrow()
        chronologicalOrderingUsesMatchTime()
        featuredScheduleOnlyIncludesImportantEvents()
        featuredScheduleFallsBackWhenNoImportantEventsExist()
        remainingScheduleExcludesFeaturedMatches()
        seriesScoreSeparatesRoundsFromMapWins()
        teamDisplayAliasesAreStable()
        print("Match logic checks passed")
    }

    private static func todayKeepsLiveAndLocalDayMatches() throws {
        var calendar = Calendar(identifier: .gregorian)
        guard
            let timeZone = TimeZone(identifier: "Asia/Shanghai"),
            let now = ISO8601DateFormatter().date(from: "2026-10-27T12:00:00Z")
        else { throw CheckError.invalidFixture }
        calendar.timeZone = timeZone

        let today = makeMatch(id: "1", startsAt: now, status: .upcoming, stars: 3)
        let tomorrowLive = makeMatch(id: "2", startsAt: now.addingTimeInterval(86_400), status: .live, stars: 1)
        let tomorrow = makeMatch(id: "3", startsAt: now.addingTimeInterval(86_400), status: .upcoming, stars: 5)
        let completedToday = makeMatch(id: "4", startsAt: now.addingTimeInterval(-100), status: .completed, stars: 4)
        let actual = [today, tomorrowLive, tomorrow, completedToday].forToday(now: now, calendar: calendar).map(\.id)

        precondition(actual == ["1", "4"], "Unexpected today filter: \(actual)")
    }

    private static func dayFilterSeparatesYesterdayTodayAndTomorrow() throws {
        var calendar = Calendar(identifier: .gregorian)
        guard
            let timeZone = TimeZone(identifier: "Asia/Shanghai"),
            let today = ISO8601DateFormatter().date(from: "2026-10-27T12:00:00Z")
        else { throw CheckError.invalidFixture }
        calendar.timeZone = timeZone
        guard
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)
        else { throw CheckError.invalidFixture }
        let matches = [
            makeMatch(id: "yesterday", startsAt: yesterday, status: .completed, stars: 1),
            makeMatch(id: "today", startsAt: today, status: .live, stars: 1),
            makeMatch(id: "tomorrow", startsAt: tomorrow, status: .upcoming, stars: 1)
        ]

        precondition(matches.forDay(yesterday, calendar: calendar).map(\.id) == ["yesterday"])
        precondition(matches.forDay(today, calendar: calendar).map(\.id) == ["today"])
        precondition(matches.forDay(tomorrow, calendar: calendar).map(\.id) == ["tomorrow"])
    }

    private static func chronologicalOrderingUsesMatchTime() {
        let now = Date()
        let lowLive = makeMatch(id: "live", startsAt: now, status: .live, stars: 1)
        let later = makeMatch(id: "later", startsAt: now.addingTimeInterval(100), status: .upcoming, stars: 5)
        let sooner = makeMatch(id: "sooner", startsAt: now.addingTimeInterval(50), status: .upcoming, stars: 5)
        let actual = [later, lowLive, sooner].chronological().map(\.id)

        precondition(actual == ["live", "sooner", "later"], "Unexpected chronological order: \(actual)")
    }

    private static func featuredScheduleOnlyIncludesImportantEvents() {
        let now = Date()
        let pgl = makeMatch(id: "pgl", event: "PGL Masters Bucharest", startsAt: now, status: .completed, stars: 1)
        let major = makeMatch(id: "major", event: "StarLadder Major", startsAt: now, status: .upcoming, stars: 1)
        let ewc = makeMatch(id: "ewc", event: "Esports World Cup", startsAt: now, status: .upcoming, stars: 1)
        let minor = makeMatch(id: "minor", event: "Regional Cup", startsAt: now, status: .live, stars: 5)
        let result = [minor, pgl, major, ewc].featuredSchedule()

        precondition(Set(result.map(\.id)) == ["pgl", "major", "ewc"], "Important event filtering failed")
    }

    private static func featuredScheduleFallsBackWhenNoImportantEventsExist() {
        let now = Date()
        let matches = (0..<6).map { index in
            makeMatch(
                id: "minor-\(index)",
                event: "Regional Cup",
                startsAt: now.addingTimeInterval(Double(index)),
                status: .upcoming,
                stars: 6 - index
            )
        }
        precondition(matches.featuredSchedule().count == 4, "Minor fallback should contain four matches")
    }

    private static func remainingScheduleExcludesFeaturedMatches() {
        let now = Date()
        let pgl = makeMatch(id: "pgl", event: "PGL Masters", startsAt: now, status: .upcoming, stars: 1)
        let minor = makeMatch(id: "minor", event: "Regional Cup", startsAt: now, status: .upcoming, stars: 5)

        precondition([minor, pgl].remainingSchedule().map(\.id) == ["minor"], "Featured match remained in the other schedule")
    }

    private static func seriesScoreSeparatesRoundsFromMapWins() {
        let legacy = makeMatch(
            id: "legacy-live",
            bestOf: "bo5",
            startsAt: Date(),
            status: .live,
            stars: 5,
            score1: "12 (2)",
            score2: "9 (1)"
        )

        precondition(legacy.mapsNeededToWin == 3, "BO5 should require three map wins")
        precondition(legacy.displayedScore1 == "12", "Legacy map wins leaked into the round score")
        precondition(legacy.seriesWins1 == 2 && legacy.seriesWins2 == 1, "Legacy series score parsing failed")
    }

    private static func teamDisplayAliasesAreStable() {
        let aliases = [
            "Ninjas in Pyjamas": "NIP",
            "Natus Vincere": "NAVI",
            "Eternal Fire": "Eternal",
            "The MongolZ": "MGLZ",
            "100 Thieves": "100T",
            "GamerLegion": "GL",
            "PARIVISION": "PV",
            "Virtus.pro": "VP"
        ]
        for (original, expected) in aliases {
            precondition(Match.displayTeamName(original) == expected, "Alias failed for \(original)")
        }
        precondition(Match.displayTeamName("Spirit") == "Spirit", "Unaliased team name changed")
    }

    private static func makeMatch(
        id: String,
        event: String = "Test Event",
        bestOf: String = "bo3",
        startsAt: Date,
        status: Match.Status,
        stars: Int,
        score1: String? = nil,
        score2: String? = nil,
        mapWins1: Int? = nil,
        mapWins2: Int? = nil
    ) -> Match {
        Match(
            id: id,
            team1: "Alpha",
            team2: "Bravo",
            team1LogoURL: nil,
            team2LogoURL: nil,
            event: event,
            stage: nil,
            bestOf: bestOf,
            startsAt: startsAt,
            status: status,
            stars: stars,
            score1: score1,
            score2: score2,
            mapWins1: mapWins1,
            mapWins2: mapWins2,
            url: URL(string: "https://www.hltv.org/matches/\(id)")!
        )
    }

    private enum CheckError: Error {
        case invalidFixture
    }
}
