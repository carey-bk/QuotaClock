import Foundation

public enum DisplaySurface: String, CaseIterable, Codable, Sendable { case menuBar, screenSaver, widget }
public struct ProviderDisplayPreference: Codable, Equatable, Sendable {
    public var menuBarVisible = true
    public var screenSaverVisible = true
    public var availableInWidgets = true
    public var heroEligible = true
    public var nickname: String?
    public var primaryProductID: String?
    public var primaryMeterID: String?
    public init() {}
    public func visible(on surface: DisplaySurface) -> Bool {
        switch surface { case .menuBar: menuBarVisible; case .screenSaver: screenSaverVisible; case .widget: availableInWidgets }
    }
}
public enum AppLogoStyle: String, Codable, CaseIterable, Sendable { case classic, glow }

public enum MenuBarIconStyle: String, Codable, CaseIterable, Sendable { case clock, provider }

public enum MenuBarAlignment: String, Codable, CaseIterable, Sendable {
    case left, center, right
    /// Left means the panel extends left from the status item's right edge.
    public func origin(anchorMin: Double, anchorMax: Double, width: Double, screenMin: Double, screenMax: Double) -> Double {
        let proposed: Double
        switch self {
        case .left: proposed = anchorMax - width
        case .center: proposed = (anchorMin + anchorMax - width) / 2
        case .right: proposed = anchorMin
        }
        return max(screenMin + 4, min(proposed, screenMax - width - 4))
    }
}
public enum MenuBarGaugeColor: String, Codable, CaseIterable, Sendable { case monochrome, color }

public struct PlatformPreferences: Codable, Equatable, Sendable {
    public var enabledProducts: Set<String> = []
    public var display: [String: ProviderDisplayPreference] = [:]
    public var menuOrder: [String] = ProviderCatalog.providers.map(\.id)
    public var saverOrder: [String] = ProviderCatalog.providers.map(\.id)
    public var appLogo: AppLogoStyle = .classic
    public var refreshPreference: RefreshPreference = .automaticOneMinute
    public var showMenuBar = true
    public var menuBarIconStyle: MenuBarIconStyle = .clock
    public var menuBarShowValue = true
    public var menuBarHeroLarge = false
    public var menuBarAlignment: MenuBarAlignment = .center
    public var menuBarGaugeColor: MenuBarGaugeColor = .monochrome
    // Retained only for decoding older installations. The app always enables accounts.
    public var codexMultiAccount = true
    public var connectionOrder: [String]?
    public var surfaces: SurfaceConfiguration?
    public var providerDisplay: ProviderDisplayConfiguration?
    public init() {}
    private enum CodingKeys: String, CodingKey { case refreshPreference, menuBarAlignment, menuBarGaugeColor, appLogo, menuBarIconStyle, menuBarShowValue, menuBarHeroLarge, enabledProducts, display, menuOrder, saverOrder, showMenuBar, codexMultiAccount, connectionOrder, surfaces, providerDisplay }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabledProducts = try c.decodeIfPresent(Set<String>.self, forKey: .enabledProducts) ?? []
        display = try c.decodeIfPresent([String: ProviderDisplayPreference].self, forKey: .display) ?? [:]
        menuOrder = try c.decodeIfPresent([String].self, forKey: .menuOrder) ?? ProviderCatalog.providers.map(\.id)
        saverOrder = try c.decodeIfPresent([String].self, forKey: .saverOrder) ?? menuOrder
        refreshPreference = try c.decodeIfPresent(RefreshPreference.self, forKey: .refreshPreference) ?? .automaticOneMinute
        showMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showMenuBar) ?? true
        appLogo = try c.decodeIfPresent(AppLogoStyle.self, forKey: .appLogo) ?? .classic
        menuBarIconStyle = try c.decodeIfPresent(MenuBarIconStyle.self, forKey: .menuBarIconStyle) ?? .clock
        menuBarAlignment = try c.decodeIfPresent(MenuBarAlignment.self, forKey: .menuBarAlignment) ?? .center
        menuBarGaugeColor = try c.decodeIfPresent(MenuBarGaugeColor.self, forKey: .menuBarGaugeColor) ?? .monochrome
        menuBarShowValue = try c.decodeIfPresent(Bool.self, forKey: .menuBarShowValue) ?? true
        menuBarHeroLarge = try c.decodeIfPresent(Bool.self, forKey: .menuBarHeroLarge) ?? false
        connectionOrder = try c.decodeIfPresent([String].self, forKey: .connectionOrder)
        surfaces = try c.decodeIfPresent(SurfaceConfiguration.self, forKey: .surfaces)
        providerDisplay = try c.decodeIfPresent(ProviderDisplayConfiguration.self, forKey: .providerDisplay)
        codexMultiAccount = try c.decodeIfPresent(Bool.self, forKey: .codexMultiAccount) ?? false
    }
    public func isProductEnabled(_ id: String) -> Bool {
        guard enabledProducts.contains(id) else { return false }
        if id == "codex.subscription" { return !codexMultiAccount }
        if id.hasPrefix("codex.subscription.account.") { return codexMultiAccount }
        return true
    }
    /// Keep the chosen style so adding the first provider restores its logo.
    public func effectiveMenuBarIconStyle(hasConfiguredProviders: Bool) -> MenuBarIconStyle {
        hasConfiguredProviders ? menuBarIconStyle : .clock
    }
    public var providerOrder: [String] {
        orderedProviders(including: [])
    }
    /// Store the user's base queue; Auto Hero promotion never rewrites this order.
    public mutating func reorderConnections(_ order: [String], available: [String]) {
        var result: [String] = []
        for id in order + available where available.contains(id) && !result.contains(id) { result.append(id) }
        connectionOrder = result
    }
    public func orderedProviders(including custom: [String]) -> [String] {
        let known = ProviderCatalog.providers.map(\.id) + custom
        var result: [String] = []
        for id in menuOrder + known where known.contains(id) && !result.contains(id) { result.append(id) }
        return result
    }
    public mutating func moveProvider(_ source: String, to target: String, including custom: [String] = []) {
        var ids = orderedProviders(including: custom)
        guard source != target, let from = ids.firstIndex(of: source), let to = ids.firstIndex(of: target) else { return }
        ids.remove(at: from); ids.insert(source, at: to)
        menuOrder = ids; saverOrder = ids
    }
    public func preference(_ id: String) -> ProviderDisplayPreference { display[id] ?? .init() }
    public static func load(defaults: UserDefaults = .standard) -> Self {
        if let data = defaults.data(forKey: "platform.preferences.v2"), let value = try? JSONDecoder().decode(Self.self, from: data) { return value }
        guard ["codex", "claude-code", "deepseek"].contains(where: { defaults.object(forKey: "provider.\($0).enabled") != nil }) else { return Self() }
        var migrated = Self()
        migrated.codexMultiAccount = false // migrate the legacy current-session connection once
        for id in ["codex", "claude-code", "deepseek"] where defaults.object(forKey: "provider.\(id).enabled") as? Bool ?? true {
            migrated.enabledProducts.insert(ProviderCatalog.legacyProductID(id))
        }
        return migrated
    }
    public func save(defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(self), forKey: "platform.preferences.v2")
    }
}
public extension ProviderQuota {
    var activeProducts: [ProductQuota] { products ?? [ProductMigration.product(self)] }
    var selectedProduct: ProductQuota? {
        let preference = displayPreference ?? .init()
        let candidates = activeProducts
        return candidates.first { $0.id == preference.primaryProductID && $0.primary(preference.primaryMeterID) != nil }
            ?? candidates.first { $0.primary() != nil } ?? candidates.first
    }
    var primaryMeter: Meter? { selectedProduct?.primary(displayPreference?.primaryMeterID) }
    /// Rebuild the v1 presentation fields from the selected product. This keeps old readers functional.
    func selecting(productID: String? = nil, meterID: String? = nil) -> Self {
        var result = self
        var preference = result.displayPreference ?? .init()
        if let productID { preference.primaryProductID = productID }
        if let meterID { preference.primaryMeterID = meterID }
        result.displayPreference = preference
        guard let product = result.selectedProduct else { return result }
        let primary = product.primary(preference.primaryMeterID)
        result.limits = product.meters.filter { $0.kind == .percentageQuota }.map {
            LimitWindow(id: $0.id, displayName: $0.displayName, remainingPercentage: NSDecimalNumber(decimal: $0.value).doubleValue,
                        resetAt: $0.resetAt, windowDuration: $0.windowDuration, isPrimary: $0.id == primary?.id)
        }
        // The legacy percentage slot must not take precedence over a selected non-percentage meter.
        if primary?.kind != .percentageQuota { result.limits = [] }
        result.balances = product.balances
        if let primary, primary.kind == .balance {
            let balance = product.balances?.first { $0.currency == primary.currency }
                ?? BalanceAmount(currency: primary.currency!, total: primary.value)
            result.balances = [balance]
        }
        result.planName = product.planName; result.health = product.health
        result.lastUpdated = product.health?.lastSuccess ?? primary?.updatedAt ?? result.lastUpdated
        result.bankResetCount = product.bankResetCount; result.usage = product.usage
        result.balanceAvailable = product.balanceAvailable
        return result
    }
}
public extension QuotaSnapshot {
    func forSurface(_ surface: DisplaySurface) -> Self {
        var result = self
        if let display = platformPreferences?.providerDisplay {
            switch surface {
            case .menuBar: result.providers = Array(providersInDisplayOrder.filter { (platformPreferences?.preference($0.id) ?? .init()).menuBarVisible }.prefix(display.effectiveMenuLimit))
            case .screenSaver: result.providers = Array(providersInDisplayOrder.filter { (platformPreferences?.preference($0.id) ?? .init()).screenSaverVisible }.prefix(display.effectiveSaverLimit))
            case .widget: result.providers = providersInConnectionOrder
            }
            return result
        }
        if let selections = platformPreferences?.surfaces {
            switch surface {
            case .menuBar:
                result.providers = selections.menu.compactMap { id in providers.first { $0.id == id } }
            case .screenSaver:
                let main = hero
                result.providers = (main.map { [$0] } ?? []) + selections.secondary.compactMap { id in
                    providers.first { $0.id == id && $0.id != main?.id }
                }
            case .widget:
                let order = platformPreferences?.connectionOrder ?? providers.map(\.id)
                result.providers = providers.sorted {
                    (order.firstIndex(of: $0.id) ?? Int.max) < (order.firstIndex(of: $1.id) ?? Int.max)
                }
            }
            return result
        }
        result.providers = providers.filter { ($0.displayPreference ?? .init()).visible(on: surface) }
        let order = surface == .screenSaver ? platformPreferences?.saverOrder : platformPreferences?.menuOrder
        if let order {
            result.providers.sort {
                let a = order.firstIndex(of: $0.id) ?? Int.max, b = order.firstIndex(of: $1.id) ?? Int.max
                return a == b ? $0.id < $1.id : a < b
            }
        }
        return result
    }
    var pinnedHeroUnavailable: Bool {
        if platformPreferences?.providerDisplay != nil { return false }
        if followsCurrentCodexAccount { return !providers.contains { $0.baseProviderID == "codex" && $0.account?.isCurrent == true } }
        if case let .pinned(id) = effectiveHeroSelection { return !providers.contains { $0.id == id } }
        return false
    }
}
