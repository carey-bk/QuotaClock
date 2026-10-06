import SwiftUI
import WidgetKit
import AppIntents
import QuotaCore
import OSLog

enum WidgetProviderChoice: String, AppEnum {
    case automatic, codex, claudeCode, deepseek
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .automatic: "Hero Provider", .codex: "Codex", .claudeCode: "Claude Code", .deepseek: "DeepSeek"
    ]
    var providerID: String? {
        switch self { case .automatic: nil; case .codex: "codex"; case .claudeCode: "claude-code"; case .deepseek: "deepseek" }
    }
}
struct WidgetMeterChoice: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Product / Metric")
    static var defaultQuery = WidgetMeterQuery()
    var id: String
    var title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
    static func identifier(provider: String, product: String, meter: String) -> String {
        String(decoding: try! JSONEncoder().encode([provider, product, meter]), as: UTF8.self)
    }
    var components: [String]? {
        guard let values = try? JSONDecoder().decode([String].self, from: Data(id.utf8)), values.count == 3 else { return nil }
        return values
    }
}
struct WidgetSourceChoice: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Account / Provider")
    static var defaultQuery = WidgetSourceQuery()
    var id: String
    var title: String
    static let hero = WidgetSourceChoice(id: WidgetDisplaySelection.heroID, title: "Hero")
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}
struct WidgetSourceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetSourceChoice] {
        let choices = try await suggestedEntities()
        return identifiers.map { id in choices.first { $0.id == id } ?? WidgetSourceChoice(id: id, title: "Unavailable account") }
    }
    func suggestedEntities() async throws -> [WidgetSourceChoice] {
        let snapshot = try? SnapshotStore(url: SnapshotLocations.shared()).read().forSurface(.widget)
        return [.hero] + (snapshot?.providers.map { WidgetSourceChoice(id: $0.id, title: $0.sourceTitle) } ?? [])
    }
}
struct WidgetMeterQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetMeterChoice] {
        // Keep missing selections resolvable so a disabled metric never silently switches to another account.
        let choices = try await suggestedEntities()
        return identifiers.map { id in choices.first { $0.id == id } ?? WidgetMeterChoice(id: id, title: "Unavailable metric") }
    }
    func suggestedEntities() async throws -> [WidgetMeterChoice] {
        guard let snapshot = try? SnapshotStore(url: SnapshotLocations.shared()).read().forSurface(.widget) else { return [] }
        return snapshot.providers.flatMap { provider in
            provider.activeProducts.flatMap { product in
                product.meters.filter(\.primaryEligible).map { meter in
                    WidgetMeterChoice(id: WidgetMeterChoice.identifier(provider: provider.id, product: product.id, meter: meter.id),
                        title: "\(provider.sourceTitle) / \(product.displayName) / \(meter.displayName)")
                }
            }
        }
    }
}

private func widgetSnapshot() -> QuotaSnapshot? { try? SnapshotStore(url: SnapshotLocations.shared()).read() }

struct WidgetFamilyChoice: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider")
    static var defaultQuery = WidgetFamilyQuery()
    var id: String
    var title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}
struct WidgetFamilyQuery: EntityQuery {
    @IntentParameterDependency<QuotaWidgetIntent>(\.$source) var sourceIntent
    @IntentParameterDependency<QuotaWidgetIntent>(\.$metric) var metricIntent
    @IntentParameterDependency<QuotaWidgetIntent>(\.$provider) var providerIntent
    func entities(for identifiers: [String]) async throws -> [WidgetFamilyChoice] {
        let choices = try await suggestedEntities()
        return identifiers.map { id in choices.first { $0.id == id } ?? WidgetFamilyChoice(id: id, title: "Unavailable provider") }
    }
    func suggestedEntities() async throws -> [WidgetFamilyChoice] {
        WidgetAccountSelection.providers(in: widgetSnapshot()).map { WidgetFamilyChoice(id: $0.id, title: $0.title) }
    }
    func defaultResult() async -> WidgetFamilyChoice? {
        let id = WidgetAccountSelection.migratedProviderID(in: widgetSnapshot(), sourceID: sourceIntent?.source.id,
            metric: metricIntent?.metric.components, legacyProviderID: providerIntent?.provider.providerID)
        return (try? await entities(for: [id]))?.first
    }
}
struct WidgetAccountChoice: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Account")
    static var defaultQuery = WidgetAccountQuery()
    var id: String
    var title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
    init(_ provider: ProviderQuota) {
        id = provider.id; title = provider.nickname ?? "Default account"
    }
    init(id: String, title: String) { self.id = id; self.title = title }
}
struct WidgetAccountQuery: EntityQuery {
    @IntentParameterDependency<QuotaWidgetIntent>(\.$family) var familyIntent
    @IntentParameterDependency<QuotaWidgetIntent>(\.$source) var sourceIntent
    @IntentParameterDependency<QuotaWidgetIntent>(\.$metric) var metricIntent
    func entities(for identifiers: [String]) async throws -> [WidgetAccountChoice] {
        let snapshot = widgetSnapshot()
        return identifiers.compactMap { id in
            if let family = familyIntent?.family.id {
                guard family != WidgetDisplaySelection.heroID else { return nil }
                let owner = WidgetAccountSelection.migratedProviderID(in: snapshot, sourceID: id, metric: nil, legacyProviderID: nil)
                guard owner == family else { return nil } // Clear a selection from a different provider.
            }
            if let value = snapshot?.displaySource(id: id, surface: .widget) { return WidgetAccountChoice(value) }
            return WidgetAccountChoice(id: id, title: "Unavailable account")
        }
    }
    func suggestedEntities() async throws -> [WidgetAccountChoice] {
        Self.choices(in: widgetSnapshot(), providerID: familyIntent?.family.id)
    }
    static func choices(in snapshot: QuotaSnapshot?, providerID: String?) -> [WidgetAccountChoice] {
        WidgetAccountSelection.accounts(in: snapshot, providerID: providerID).map(WidgetAccountChoice.init)
    }
    func defaultResult() async -> WidgetAccountChoice? {
        WidgetAccountSelection.defaultAccount(in: widgetSnapshot(), providerID: familyIntent?.family.id,
            legacySourceID: sourceIntent?.source.id, legacyMetric: metricIntent?.metric.components).map(WidgetAccountChoice.init)
    }
}

struct QuotaWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "QuotaClock Provider"
    static var description = IntentDescription("Choose the provider shown in this widget.")
    @Parameter(title: "Provider") var provider: WidgetProviderChoice?
    @Parameter(title: "Account / Provider") var source: WidgetSourceChoice?
    @Parameter(title: "Product / Metric") var metric: WidgetMeterChoice?
    @Parameter(title: "Provider") var family: WidgetFamilyChoice?
    @Parameter(title: "Account") var account: WidgetAccountChoice?
    static var parameterSummary: some ParameterSummary {
        // AppIntents metadata extraction requires a literal identifier here.
        When(\.$family, identifier: .equalTo, "quotaclock.hero") {
            Summary("\(\.$family)")
        } otherwise: {
            Summary("\(\.$family)") { \.$account }
        }
    }
    init() { provider = .automatic }
}
struct QuotaEntry: TimelineEntry {
    let date: Date
    let snapshot: QuotaSnapshot?
    let configuration: QuotaWidgetIntent
}
struct QuotaTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry { QuotaEntry(date: .now, snapshot: nil, configuration: QuotaWidgetIntent()) }
    func snapshot(for configuration: QuotaWidgetIntent, in context: Context) async -> QuotaEntry { read(configuration) }
    func timeline(for configuration: QuotaWidgetIntent, in context: Context) async -> Timeline<QuotaEntry> {
        Timeline(entries: [read(configuration)], policy: .after(Date().addingTimeInterval(900)))
    }
    private func read(_ configuration: QuotaWidgetIntent) -> QuotaEntry {
        let logger = Logger(subsystem: "com.quotaclock", category: "widget")
        let snapshot: QuotaSnapshot?
        do {
            let value = try SnapshotStore(url: SnapshotLocations.shared()).read()
            snapshot = value
            logger.notice("Read revision=\(value.revision.uuidString, privacy: .public)")
        } catch {
            snapshot = nil
            logger.error("Could not read shared snapshot: \(error.localizedDescription, privacy: .public)")
        }
        return QuotaEntry(date: .now, snapshot: snapshot, configuration: configuration)
    }
}
struct QuotaWidgetView: View {
    let entry: QuotaEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var language: AppLanguage {
        AppLanguage(rawValue: UserDefaults(suiteName: SnapshotLocations.appGroup)?.string(forKey: "ui.widgetLanguage") ?? "english") ?? .english
    }
    private var provider: ProviderQuota? {
        guard let snapshot = entry.snapshot else { return nil }
        return WidgetAccountSelection.provider(in: snapshot, providerID: entry.configuration.family?.id, accountID: entry.configuration.account?.id,
            legacySourceID: entry.configuration.source?.id, legacyMetric: entry.configuration.metric.map { $0.components ?? [] },
            legacyProviderID: entry.configuration.provider?.providerID)
    }
    var body: some View {
        WidgetCardContent(provider: provider, family: family, language: language, renderingMode: renderingMode)
            .containerBackground(for: .widget) {
                if renderingMode == .fullColor { WidgetCardBackground() }
                else { Color.clear }
            }
    }
}
@main struct QuotaClockWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: SnapshotLocations.widgetKind, intent: QuotaWidgetIntent.self, provider: QuotaTimelineProvider()) { QuotaWidgetView(entry: $0) }
            .configurationDisplayName("QuotaClock")
            .description("Live provider quota or balance · Small, Medium, Large")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
            .contentMarginsDisabled()
            .containerBackgroundRemovable(true)
    }
}
