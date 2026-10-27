import Foundation
import WebKit

@MainActor
final class HLTVScraper: NSObject, WKNavigationDelegate {
    private struct EventSource: Decodable {
        let id: String
        let name: String
        let url: URL
    }

    enum ScrapeError: LocalizedError {
        case alreadyLoading
        case invalidResponse
        case pageUnavailable
        case timedOut

        var errorDescription: String? {
            switch self {
            case .alreadyLoading: return "正在刷新，请稍候"
            case .invalidResponse: return "HLTV 返回了无法识别的数据"
            case .pageUnavailable: return "暂时无法读取 HLTV 比赛页面"
            case .timedOut: return "连接 HLTV 超时"
            }
        }
    }

    private let webView: WKWebView
    private var continuation: CheckedContinuation<[Match], Error>?
    private var pollingTask: Task<Void, Never>?
    private var isFetchingSupplemental = false

    override init() {
        let matchesConfiguration = WKWebViewConfiguration()
        matchesConfiguration.websiteDataStore = .default()
        matchesConfiguration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .init(x: 0, y: 0, width: 390, height: 700), configuration: matchesConfiguration)
        super.init()
        webView.navigationDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    }

    func fetchMatches() async throws -> [Match] {
        guard continuation == nil else { throw ScrapeError.alreadyLoading }
        guard let url = URL(string: "https://www.hltv.org/matches") else {
            throw ScrapeError.pageUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 30
            webView.load(request)
            beginPolling()
        }
    }

    private func beginPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<30 {
                if Task.isCancelled { return }
                try? await Task.sleep(for: .seconds(1))
                do {
                    if let scheduled = try await self.extractMatches(), !scheduled.isEmpty {
                        let events = (try? await self.extractImportantEventSources()) ?? []
                        let completed = await self.fetchCompletedMatches(from: events)
                        self.finish(.success(self.merge(scheduled: scheduled, completed: completed)))
                        return
                    }
                } catch {
                    // The document can be replaced while Cloudflare finishes its check.
                }
            }
            self.finish(.failure(ScrapeError.timedOut))
        }
    }

    private func extractMatches() async throws -> [Match]? {
        let value = try await webView.evaluateJavaScript(Self.extractionScript)
        guard let json = value as? String else { return nil }
        let data = Data(json.utf8)
        do {
            return try JSONDecoder.hltv.decode([Match].self, from: data)
        } catch {
            throw ScrapeError.invalidResponse
        }
    }

    private func extractImportantEventSources() async throws -> [EventSource] {
        let value = try await webView.evaluateJavaScript(Self.eventSourcesScript)
        guard let json = value as? String else { return [] }
        let sources = try JSONDecoder().decode([EventSource].self, from: Data(json.utf8))
        return sources.filter { Match.isImportantEventName($0.name) }
    }

    private func fetchCompletedMatches(from events: [EventSource]) async -> [Match] {
        isFetchingSupplemental = true
        defer { isFetchingSupplemental = false }
        var matchesByID: [String: Match] = [:]
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        for event in events {
            if Task.isCancelled { break }
            webView.load(URLRequest(url: event.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))

            for _ in 0..<20 {
                if Task.isCancelled { break }
                try? await Task.sleep(for: .milliseconds(500))
                guard let eventMatches = try? await extractCompletedEventMatches() else { continue }
                for match in eventMatches where calendar.isDateInToday(match.startsAt)
                    || calendar.isDate(match.startsAt, inSameDayAs: yesterday) {
                    matchesByID[match.id] = match
                }
                break
            }
        }
        return Array(matchesByID.values).chronological()
    }

    private func extractCompletedEventMatches() async throws -> [Match]? {
        let value = try await webView.evaluateJavaScript(Self.eventResultsExtractionScript)
        guard let json = value as? String else { return nil }
        return try JSONDecoder.hltv.decode([Match].self, from: Data(json.utf8))
    }

    private func merge(scheduled: [Match], completed: [Match]) -> [Match] {
        var byID = Dictionary(uniqueKeysWithValues: completed.map { ($0.id, $0) })
        for match in scheduled {
            byID[match.id] = match
        }
        return Array(byID.values).chronological()
    }

    private func finish(_ result: Result<[Match], Error>) {
        guard let continuation else { return }
        self.continuation = nil
        pollingTask?.cancel()
        pollingTask = nil
        webView.stopLoading()
        continuation.resume(with: result)
    }

    func exportValveTopTeamLogos() async throws -> Int {
        guard let url = URL(string: "https://www.hltv.org/valve-ranking/teams") else {
            throw ScrapeError.pageUnavailable
        }
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))

        for _ in 0..<60 {
            if Task.isCancelled { throw CancellationError() }
            try await Task.sleep(for: .seconds(1))
            let rawCount = try? await webView.evaluateJavaScript(
                "document.querySelectorAll('.ranking-header').length"
            )
            let count = (rawCount as? NSNumber)?.intValue ?? (rawCount as? Int) ?? 0
            if count >= 50 {
                _ = try? await webView.evaluateJavaScript("window.scrollTo(0, 3200); true")
                try await Task.sleep(for: .seconds(3))
                return try await cacheVisibleTeamLogos(limit: 50, containerSelector: ".ranking-header")
            }
        }
        throw ScrapeError.timedOut
    }

    @discardableResult
    private func cacheVisibleTeamLogos(
        limit: Int,
        containerSelector: String = ".match-team"
    ) async throws -> Int {
        let preparationScript = #"""
        (() => {
          const selector = \#(String(reflecting: containerSelector));
          const limit = \#(limit);
          const seen = new Set();
          const items = [];
          for (const container of document.querySelectorAll(selector)) {
            const images = [...container.querySelectorAll('img')];
            const image = images.find(img => img.classList.contains('night-only') && img.complete && img.naturalWidth > 0)
              || images.find(img => img.complete && img.naturalWidth > 0)
              || images[0];
            const name = (image?.alt || image?.title || '').trim();
            if (!image || !name || seen.has(name) || !image.complete || image.naturalWidth === 0) continue;
            seen.add(name);
            items.push({ name, image });
            if (items.length >= limit) break;
          }
          if (!items.length) return [];

          const overlay = document.createElement('div');
          overlay.id = 'csmatch-logo-grid';
          Object.assign(overlay.style, {
            display: 'grid', gridTemplateColumns: 'repeat(8, 50px)', gridAutoRows: '50px',
            gap: '8px', padding: '8px', width: '472px', boxSizing: 'border-box',
            background: '#242426', margin: '0'
          });
          for (const item of items) {
            const cell = document.createElement('div');
            Object.assign(cell.style, {
              width: '50px', height: '50px', display: 'flex', alignItems: 'center',
              justifyContent: 'center', overflow: 'hidden', background: '#242426'
            });
            Object.assign(item.image.style, {
              display: 'block', width: '46px', height: '46px', maxWidth: '46px',
              maxHeight: '46px', objectFit: 'contain', visibility: 'visible', opacity: '1'
            });
            cell.appendChild(item.image);
            overlay.appendChild(cell);
          }
          document.body.replaceChildren(overlay);
          document.documentElement.style.margin = '0';
          document.documentElement.style.background = '#242426';
          document.body.style.margin = '0';
          document.body.style.background = '#242426';
          return items.map(item => item.name);
        })();
        """#

        guard let names = try await webView.evaluateJavaScript(preparationScript) as? [String], !names.isEmpty else {
            return 0
        }
        try? await Task.sleep(for: .milliseconds(250))

        let columns = 8
        let cellSize: CGFloat = 50
        let gap: CGFloat = 8
        let rows = Int(ceil(Double(names.count) / Double(columns)))
        let width = gap + CGFloat(columns) * (cellSize + gap)
        let height = gap + CGFloat(rows) * (cellSize + gap)
        webView.setFrameSize(NSSize(width: width, height: height))

        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: width, height: height)
        configuration.afterScreenUpdates = true
        let snapshot = try await takeSnapshot(configuration: configuration)
        let xScale = snapshot.size.width / width
        let yScale = snapshot.size.height / height

        for (index, name) in names.enumerated() {
            let column = index % columns
            let row = index / columns
            let sourceRect = NSRect(
                x: (gap + CGFloat(column) * (cellSize + gap)) * xScale,
                y: (height - gap - CGFloat(row + 1) * cellSize - CGFloat(row) * gap) * yScale,
                width: cellSize * xScale,
                height: cellSize * yScale
            )
            let logo = NSImage(size: NSSize(width: cellSize, height: cellSize))
            logo.lockFocus()
            snapshot.draw(
                in: NSRect(x: 0, y: 0, width: cellSize, height: cellSize),
                from: sourceRect,
                operation: .copy,
                fraction: 1
            )
            logo.unlockFocus()
            TeamLogoCache.shared.store(logo, for: name)
        }
        return names.count
    }

    private func takeSnapshot(configuration: WKSnapshotConfiguration) async throws -> NSImage {
        try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: configuration) { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? ScrapeError.invalidResponse)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView === self.webView && !isFetchingSupplemental {
            finish(.failure(error))
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView === self.webView && !isFetchingSupplemental {
            finish(.failure(error))
        }
    }

    private static let extractionScript = #"""
    (() => {
      const clean = value => (value || '').replace(/\s+/g, ' ').trim();
      const absolute = value => value ? new URL(value, location.origin).href : null;
      const candidates = [
        ...document.querySelectorAll('.match-wrapper[data-match-id]'),
        ...document.querySelectorAll('.match[data-livescore-match]')
      ];
      const seen = new Set();
      const result = [];

      for (const candidate of candidates) {
        const root = candidate.matches('.match') ? candidate : candidate.querySelector('.match');
        if (!root) continue;
        const link = root.querySelector('a[href^="/matches/"]');
        const href = link?.getAttribute('href');
        if (!href || seen.has(href)) continue;

        const teams = [...root.querySelectorAll('.match-teamname')];
        if (teams.length < 2) continue;
        const wrapper = root.closest('[data-match-wrapper], [data-livescore-match]') || root;
        const matchID = wrapper.dataset.matchId || wrapper.dataset.livescoreMatch || href.split('/')[2];
        const isLive = root.querySelector('.match-meta-live') !== null || wrapper.getAttribute('live') === 'true';
        const zone = root.closest('.match-zone-wrapper');
        const timestamp = Number(
          root.querySelector('.match-time[data-unix]')?.dataset.unix
          || zone?.dataset.zonedgroupingEntryUnix
          || Date.now()
        );
        const eventElement = root.querySelector('.match-event');
        const eventHeader = root.closest('.matches-event-wrapper')?.querySelector('.event-headline-wrapper');
        const eventName = clean(
          eventElement?.dataset.eventHeadline
          || eventElement?.querySelector('.text-ellipsis')?.textContent
          || eventHeader?.dataset.eventHeadline
          || eventHeader?.querySelector('.event-headline-text')?.childNodes[0]?.textContent
          || 'HLTV'
        );
        const meta = [...root.querySelectorAll('.match-info .match-meta')].map(element => clean(element.textContent));
        const starsFromAttribute = Number(wrapper.dataset.stars);
        const starsFromIcons = root.querySelectorAll('.match-rating i:not(.faded)').length;
        const teamData = teams.slice(0, 2).map(team => {
          const row = team.closest('.match-team');
          const image = row?.querySelector('img.match-team-logo:not(.night-only)') || row?.querySelector('img.match-team-logo');
          return { name: clean(team.textContent), logo: absolute(image?.getAttribute('src')) };
        });
        const scoreRows = [...root.querySelectorAll('.match-team-score')].slice(0, 2);
        const score = scoreRows.map(row => {
          const current = clean(row.querySelector('.current-map-score')?.textContent);
          return current || null;
        });
        const mapWins = scoreRows.map(row => {
          const value = Number(clean(row.querySelector('[data-livescore-maps-won-for]')?.textContent));
          return Number.isFinite(value) ? value : 0;
        });

        seen.add(href);
        result.push({
          id: String(matchID),
          team1: teamData[0].name,
          team2: teamData[1].name,
          team1LogoURL: teamData[0].logo,
          team2LogoURL: teamData[1].logo,
          event: eventName,
          stage: clean(root.querySelector('.match-stage')?.textContent) || null,
          bestOf: meta.find(value => /^bo\d$/i.test(value)) || '',
          startsAt: new Date(timestamp).toISOString(),
          status: isLive ? 'live' : 'upcoming',
          stars: Number.isFinite(starsFromAttribute) ? starsFromAttribute : starsFromIcons,
          score1: score[0] || null,
          score2: score[1] || null,
          mapWins1: isLive ? mapWins[0] : null,
          mapWins2: isLive ? mapWins[1] : null,
          url: absolute(href)
        });
      }
      return JSON.stringify(result);
    })();
    """#

    private static let eventSourcesScript = #"""
    (() => {
      const seen = new Set();
      const events = [];
      const elements = [
        ...document.querySelectorAll('.match-event[data-event-id]'),
        ...document.querySelectorAll('.event-headline-wrapper[data-event-id]')
      ];
      for (const element of elements) {
        const id = element.dataset.eventId;
        const name = (
          element.dataset.eventHeadline
          || element.querySelector('.event-headline-text')?.childNodes[0]?.textContent
          || element.textContent
          || ''
        ).replace(/\s+/g, ' ').trim();
        if (!id || !name || seen.has(id)) continue;
        const href = element.querySelector('a[href^="/events/"]')?.getAttribute('href');
        if (!href) continue;
        seen.add(id);
        events.push({ id, name, url: new URL(href, location.origin).href });
      }
      return JSON.stringify(events);
    })();
    """#

    private static let eventResultsExtractionScript = #"""
    (() => {
      if (!document.querySelector('a[href*="/results?event="]')) return null;
      const clean = value => (value || '').replace(/\s+/g, ' ').trim();
      const absolute = value => value ? new URL(value, location.origin).href : null;
      const eventName = clean(document.querySelector('h1')?.textContent || 'HLTV');
      const seen = new Set();
      const result = [];

      for (const link of document.querySelectorAll('a.bottom-row[href^="/matches/"]')) {
        const href = link.getAttribute('href');
        const timestamp = Number(link.querySelector('[data-unix]')?.dataset.unix || 0);
        const score1 = clean(link.querySelector('.score-left')?.textContent);
        const score2 = clean(link.querySelector('.score-right')?.textContent);
        const team1Row = link.querySelector('.group-team.team-1');
        const team2Row = link.querySelector('.group-team.team-2');
        const team1 = clean(team1Row?.querySelector('span.text-ellipsis')?.textContent);
        const team2 = clean(team2Row?.querySelector('span.text-ellipsis')?.textContent);
        if (!href || seen.has(href) || timestamp <= 0 || !team1 || !team2 || !score1 || !score2) continue;
        if (!/^\d+$/.test(score1) || !/^\d+$/.test(score2)) continue;

        const team1Image = team1Row?.querySelector('img');
        const team2Image = team2Row?.querySelector('img');
        seen.add(href);
        result.push({
          id: String(href.split('/')[2]),
          team1,
          team2,
          team1LogoURL: absolute(team1Image?.getAttribute('src')),
          team2LogoURL: absolute(team2Image?.getAttribute('src')),
          event: eventName,
          stage: null,
          bestOf: clean(link.querySelector('.group-right')?.textContent),
          startsAt: new Date(timestamp).toISOString(),
          status: 'completed',
          stars: 0,
          score1,
          score2,
          mapWins1: Number(score1),
          mapWins2: Number(score2),
          url: absolute(href)
        });
      }
      return JSON.stringify(result);
    })();
    """#
}

private extension JSONDecoder {
    static var hltv: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
