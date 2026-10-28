import AppKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: MatchesStore
    @EnvironmentObject private var douyuLive: DouyuLiveStore

    private static let headerImage: NSImage = {
        guard
            let url = Bundle.main.url(forResource: "HeaderIcon@2x", withExtension: "jpg"),
            let image = NSImage(contentsOf: url)
        else {
            return NSImage(systemSymbolName: "scope", accessibilityDescription: "CS Match Desk")
                ?? NSImage(size: NSSize(width: 36, height: 36))
        }
        return image
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            filterBar
            content
            Divider().opacity(0.45)
            footer
        }
        .frame(width: 390, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .onAppear {
            store.resetToToday()
        }
        .task {
            await douyuLive.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: Self.headerImage)
                .resizable()
                .scaledToFill()
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("CS Match Desk")

            VStack(alignment: .leading, spacing: 2) {
                Text("CS MATCH DESK")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(store.selectedDate.formatted(.dateTime.month(.wide).day().weekday(.wide)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if store.liveCount > 0 {
                HStack(spacing: 5) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text("\(store.liveCount) LIVE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.red)
            }

            Button {
                Task { await store.refresh() }
                Task { await douyuLive.refresh(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                    .animation(store.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: store.isRefreshing)
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)
            .help("刷新比赛")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var filterBar: some View {
        HStack(spacing: 9) {
            Picker("比赛范围", selection: $store.filter) {
                ForEach(MatchesStore.Filter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 124)

            Spacer()

            Picker("比赛日期", selection: $store.selectedDay) {
                ForEach(MatchesStore.DaySelection.allCases) { day in
                    Text(store.dayTitle(for: day)).tag(day)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 154)

            Text("\(store.visibleMatches.count) 场")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if store.isRefreshing && store.matches.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("正在同步今日赛程")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = store.errorMessage, store.matches.isEmpty {
            EmptyState(icon: "wifi.exclamationmark", title: "暂时无法同步", detail: error)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.visibleMatches.isEmpty {
            EmptyState(icon: "moon.stars", title: "今天暂无比赛", detail: "稍后刷新再看看")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(store.visibleGroups) { group in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 6) {
                                Text(group.event)
                                    .font(.caption.weight(.bold))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(group.matches.count) 场")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 4)

                            ForEach(group.matches) { match in
                                MatchCard(match: match) {
                                    store.open(match)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Group {
                if let updated = store.lastUpdated {
                    Text("更新于 \(updated.formatted(date: .omitted, time: .shortened))")
                } else {
                    Text("等待首次同步")
                }
            }
            .font(.caption2)
            .foregroundStyle(store.errorMessage == nil ? Color.secondary : Color.orange)

            Spacer()

            douyuRoomButton

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("退出")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var douyuRoomButton: some View {
        Button {
            NSWorkspace.shared.open(DouyuRoomClient.roomURL)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(douyuStatusColor)
                    .frame(width: 6, height: 6)
                Text("玩机器")
                    .foregroundStyle(.primary)
                Text(douyuLive.status.title)
                    .foregroundStyle(douyuStatusColor)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 10, weight: .medium))
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(douyuStatusColor.opacity(0.1), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(douyuRoomHelp)
        .accessibilityLabel("玩机器，\(douyuLive.status.title)，打开斗鱼直播间 6657")
    }

    private var douyuStatusColor: Color {
        switch douyuLive.status {
        case .live: return .red
        case .unavailable: return .orange
        case .checking, .offline: return .secondary
        }
    }

    private var douyuRoomHelp: String {
        let detail: String
        if let checked = douyuLive.lastChecked {
            detail = "\(douyuLive.status.title) · 检查于 \(checked.formatted(date: .omitted, time: .shortened))"
        } else if douyuLive.status == .unavailable {
            detail = "暂时无法获取直播状态"
        } else {
            detail = "正在查询直播状态"
        }
        return "玩机器 · \(detail)\n点击打开斗鱼直播间 6657"
    }
}

private struct MatchCard: View {
    let match: Match
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                HStack(spacing: 8) {
                    if let stage = match.stage, !stage.isEmpty {
                        Text(stage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    stars
                    status
                }

                HStack(spacing: 6) {
                    team(name: match.team1, logo: match.team1LogoURL)
                    scoreboard
                    team(name: match.team2, logo: match.team2LogoURL, trailing: true)
                }

                HStack {
                    if match.status == .completed {
                        Text("最终比分")
                    }
                    Spacer()
                    if !match.bestOf.isEmpty {
                        Text(match.bestOf.uppercased())
                    }
                    Image(systemName: "arrow.up.right")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(match.status == .live ? Color.red.opacity(0.42) : Color.white.opacity(0.06))
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(MatchButtonStyle())
    }

    private var status: some View {
        Group {
            switch match.status {
            case .live:
                Text("LIVE")
                    .foregroundStyle(.red)
            case .upcoming:
                Text(match.startsAt.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(.primary)
            case .completed:
                Text("已结束")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11, weight: .bold, design: .monospaced))
    }

    private var stars: some View {
        HStack(spacing: 1) {
            ForEach(0..<min(match.stars, 5), id: \.self) { _ in
                Image(systemName: "star.fill")
            }
        }
        .font(.system(size: 7))
        .foregroundStyle(.yellow)
    }

    private var scoreboard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                scoreText(match.displayedScore1, alignment: .trailing)
                Text(match.status == .completed ? "-" : "VS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18)
                scoreText(match.displayedScore2, alignment: .leading)
            }

            if let requiredWins = match.mapsNeededToWin {
                HStack(spacing: 5) {
                    seriesIndicator(wins: match.seriesWins1, requiredWins: requiredWins, trailing: true)
                    Color.clear.frame(width: 18, height: 4)
                    seriesIndicator(wins: match.seriesWins2, requiredWins: requiredWins, trailing: false)
                }
            }
        }
        .frame(width: 116)
    }

    private func seriesIndicator(wins: Int, requiredWins: Int, trailing: Bool) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<requiredWins, id: \.self) { index in
                Capsule()
                    .fill(index < wins ? Color.primary.opacity(0.9) : Color.primary.opacity(0.16))
                    .frame(width: 9, height: 4)
            }
        }
        .frame(width: 44, alignment: trailing ? .trailing : .leading)
        .accessibilityLabel("已赢 \(wins) 张地图，共需 \(requiredWins) 张")
    }

    private func team(name: String, logo: URL?, trailing: Bool = false) -> some View {
        HStack(spacing: 7) {
            if trailing {
                nameText(name)
                TeamLogo(url: logo, name: name)
            } else {
                TeamLogo(url: logo, name: name)
                nameText(name)
            }
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }

    private func nameText(_ name: String) -> some View {
        Text(Match.displayTeamName(name))
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
    }

    private func scoreText(_ score: String?, alignment: Alignment) -> some View {
        Text(score ?? "")
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .frame(width: 44, alignment: alignment)
    }
}

private struct TeamLogo: View {
    @Environment(\.colorScheme) private var colorScheme
    let url: URL?
    let name: String
    @ObservedObject private var cache = TeamLogoCache.shared

    var body: some View {
        Group {
            if let image = cache.image(for: name, darkMode: colorScheme == .dark) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                fallback
            }
        }
        .frame(width: 26, height: 26)
    }

    private var fallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06))
            Text(String(name.prefix(1)).uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
    }
}

private struct EmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
    }
}

private struct MatchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
