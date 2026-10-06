import SwiftUI
import QuotaCore

struct AmbientPreviewView: View {
    @ObservedObject var model: SnapshotController
    @State private var shape = "16:9"
    @State private var count = 3
    @State private var condition = "Normal"
    @State private var useFixture = false
    @State private var fixtureHero = "Codex"
    private var language: AppLanguage { model.preferences.language }
    private func t(_ key: String) -> String { AppText.value(key, language) }
    private var dimensions: CGSize {
        switch shape {
        case "16:10": CGSize(width: 800, height: 500)
        case "21:9": CGSize(width: 840, height: 360)
        case "32:9": CGSize(width: 900, height: 254)
        case "Portrait": CGSize(width: 360, height: 640)
        case "System Preview": CGSize(width: 340, height: 220)
        default: CGSize(width: 800, height: 450)
        }
    }
    private var shownSnapshot: QuotaSnapshot? {
        guard useFixture else { return model.snapshot?.displayProjection() }
        var providers: [ProviderQuota] = []
        for index in 0..<count {
            if index == 0 && (fixtureHero == "DeepSeek" || condition == "Large balance") {
                providers.append(ProviderQuota(id: "deepseek", displayName: "DeepSeek", planName: nil, limits: [],
                    lastUpdated: .now, balances: [BalanceAmount(currency: "CNY", total: condition == "Large balance" ? 1_234_567.89 : 4.90, granted: 0, toppedUp: 4.90)], balanceAvailable: true))
            } else {
                let id = index == 0 ? "codex" : "sample-\(index)"
                let name = index == 0 ? "Codex" : index == 1 ? "Claude Code" : "Provider \(index + 1)"
                let history = (0..<7).map { day in
                    UsageDay(date: .now.addingTimeInterval(Double(day - 6) * 86400),
                             tokens: Int64([12, 23, 36, 29, 54, 76, 42][day]) * 1_000_000)
                }
                providers.append(ProviderQuota(id: id, displayName: name, planName: index == 0 ? "Pro" : nil,
                    limits: index == 0 ? [
                        LimitWindow(id: "5h", displayName: "5-hour", remainingPercentage: 19,
                                    resetAt: .now.addingTimeInterval(7200), isPrimary: true),
                        LimitWindow(id: "weekly", displayName: "Weekly", remainingPercentage: 18)
                    ] : [LimitWindow(id: "weekly", displayName: "Weekly", remainingPercentage: Double(90 - index * 7),
                                     resetAt: .now.addingTimeInterval(7200), isPrimary: true)],
                    lastUpdated: .now, bankResetCount: index == 0 ? 2 : nil,
                    usage: index == 0 ? UsageStatistics(totalTokens: 342_200_000, dailyHistory: history) : nil))
            }
        }
        if condition == "Authentication" {
            providers[0].limits = []; providers[0].balances = nil
            providers[0].health = ProviderHealth(state: .authenticationRequired)
        } else if condition == "No data" {
            providers[0].limits = []; providers[0].balances = nil
            providers[0].health = ProviderHealth(state: .unavailable)
        } else if condition == "Stale" {
            providers[0].health = ProviderHealth(state: .stale, lastSuccess: .now.addingTimeInterval(-3600), usingLastKnownGood: true)
        } else if condition == "0%" || condition == "100%" {
            if !providers[0].limits.isEmpty { providers[0].limits[0].remainingPercentage = condition == "0%" ? 0 : 100 }
        } else if condition == "Long names" {
            providers[0].displayName = "Provider With An Extremely Long Name"
            providers[0].planName = "Experimental Long Plan"
            if !providers[0].limits.isEmpty { providers[0].limits[0].displayName = "Extra Long Weekly Limit Name" }
        }
        var snapshot = QuotaSnapshot(generatedAt: .now, providers: providers)
        snapshot.heroSelection = .pinned(providerID: providers[0].id)
        return snapshot
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Toggle(t("Sample data"), isOn: $useFixture)
                Picker(t("Screen shape"), selection: $shape) {
                    ForEach(["16:9", "16:10", "21:9", "32:9", "Portrait", "System Preview"], id: \.self) { Text($0).tag($0) }
                }.frame(width: 210)
            }
            HStack {
                    Picker(t("Provider count"), selection: $count) { ForEach([1,2,3], id: \.self) { Text("\($0)").tag($0) } }
                    Picker(t("Condition"), selection: $condition) {
                        ForEach(["Normal", "Stale", "Authentication", "No data", "0%", "100%", "Long names", "Large balance"], id: \.self) { Text(t($0)).tag($0) }
                    }
                    Picker(t("Hero Provider"), selection: $fixtureHero) {
                        Text("Codex").tag("Codex"); Text("DeepSeek").tag("DeepSeek")
                    }
            }.frame(height: 28).opacity(useFixture ? 1 : 0).disabled(!useFixture).accessibilityHidden(!useFixture)
            GeometryReader { available in
                let size = dimensions
                let scale = min(available.size.width / size.width, available.size.height / size.height, 1)
                let renderSize = CGSize(width: size.width * scale, height: size.height * scale)
                TimelineView(.periodic(from: .now, by: 15)) { timeline in
                    AmbientDisplay(snapshot: shownSnapshot, preferences: model.preferences, now: timeline.date,
                        page: 0, preview: shape == "System Preview", accelerated: false, allowsMotion: false)
                        .frame(width: renderSize.width, height: renderSize.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }.padding(18).frame(minWidth: 650, minHeight: 530).toggleStyle(CompactSwitchStyle())
    }
}
