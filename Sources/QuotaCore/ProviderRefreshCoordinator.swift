import Foundation

/// Main-app owner. Scheduling, health, backoff and reconciliation are per Product.
public actor ProviderRefreshCoordinator {
    private var adapters: [String: any ProductAdapter]
    private let publisher: SnapshotPublisher
    private var snapshot: QuotaSnapshot
    private var preferences: PlatformPreferences
    private var products: [String: ProductQuota] = [:]
    private var failures: [String: Int] = [:]
    private var retryAfter: [String: Date] = [:]
    private var inFlight: Set<String> = []
    private var generation: [String: Int] = [:]
    private var publicationFailed = false
    private var refreshAfterCredentialChange: Set<String> = []
    public static let freshnessThreshold: TimeInterval = 15 * 60

    public init(adapters: [any ProductAdapter], publisher: SnapshotPublisher, existing: QuotaSnapshot?, preferences: PlatformPreferences) {
        self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.descriptor.id, $0) })
        self.publisher = publisher; self.preferences = preferences
        snapshot = existing ?? QuotaSnapshot(generatedAt: .now, providers: [])
        for provider in snapshot.providers where provider.health != nil {
            for product in provider.activeProducts { products[product.id] = product }
        }
        let activeProviders = Set(products.values.filter { preferences.isProductEnabled($0.id) }.map(\.sourceID))
        snapshot.providers.removeAll { !activeProviders.contains($0.id) || $0.health == nil }
    }
    public init(adapters: [any ProviderAdapter], publisher: SnapshotPublisher, existing: QuotaSnapshot?, enabled: Set<String>) {
        let wrapped = adapters.map { LegacyProductAdapter($0) }
        self.adapters = Dictionary(uniqueKeysWithValues: wrapped.map { ($0.descriptor.id, $0) })
        self.publisher = publisher
        var prefs = PlatformPreferences(); prefs.codexMultiAccount = false
        prefs.enabledProducts = Set(enabled.map(ProviderCatalog.legacyProductID))
        preferences = prefs
        snapshot = existing ?? QuotaSnapshot(generatedAt: .now, providers: [])
        for provider in snapshot.providers where provider.health != nil {
            for product in provider.activeProducts { products[product.id] = product }
        }
        snapshot.providers.removeAll { !enabled.contains($0.id) || $0.health == nil }
    }
    public func register(_ adapter: any ProductAdapter) {
        let id = adapter.descriptor.id
        generation[id, default: 0] += 1
        adapters[id] = adapter
        refreshAfterCredentialChange.insert(id)
        retryAfter[id] = nil; failures[id] = nil
        if let account = adapter as? CodexAccountAdapter {
            if products[id] == nil {
                products[id] = ProductQuota(id: id, providerID: adapter.descriptor.providerID,
                    displayName: adapter.descriptor.displayName, meters: [], at: .distantPast)
            }
            products[id]?.account = account.presentation
        }
    }
    public func register(_ registrations: [any ProductAdapter]) {
        // Apply every current-account marker in one actor turn, before any refresh can publish.
        for adapter in registrations { register(adapter) }
    }
    public func unregister(_ id: String) {
        generation[id, default: 0] += 1
        adapters[id] = nil; products[id] = nil; retryAfter[id] = nil
    }
    public func current() -> QuotaSnapshot { snapshot }
    public func lastPublicationFailed() -> Bool { publicationFailed }
    public func setEnabled(_ ids: Set<String>) throws -> QuotaSnapshot {
        var next = preferences
        next.enabledProducts = Set(adapters.values.filter { ids.contains($0.descriptor.providerID) }.map { $0.descriptor.id })
        return try configure(next)
    }
    public func configure(_ next: PlatformPreferences) throws -> QuotaSnapshot {
        for id in preferences.enabledProducts.union(next.enabledProducts)
            where preferences.isProductEnabled(id) != next.isProductEnabled(id) {
            generation[id, default: 0] += 1
            retryAfter[id] = nil; failures[id] = 0
        }
        preferences = next
        return try publish(at: .now)
    }
    public func setHero(_ selection: HeroSelection) throws -> QuotaSnapshot {
        snapshot.heroSelection = selection
        return try publish(at: .now)
    }
    public func hasAutomaticRefreshDue(at date: Date = .now) -> Bool {
        preferences.enabledProducts.contains { id in
            guard preferences.isProductEnabled(id), let adapter = adapters[id], !inFlight.contains(id) else { return false }
            return refreshAfterCredentialChange.contains(id) || preferences.refreshPreference.nextRefresh(after: products[id]?.health?.lastAttempt,
                minimum: adapter.minimumRefreshInterval, retryAfter: retryAfter[id]) <= date
        }
    }
    public func refreshAll(manual: Bool = false, onUpdate: @Sendable (QuotaSnapshot) async -> Void) async {
        await refresh(ids: preferences.enabledProducts.sorted(), manual: manual, onUpdate: onUpdate)
    }
    public func refresh(providerID: String, onUpdate: @Sendable (QuotaSnapshot) async -> Void) async {
        await refresh(ids: adapters.values.filter { $0.descriptor.providerID == providerID }.map { $0.descriptor.id }, manual: true, onUpdate: onUpdate)
    }
    public func refresh(productID: String, onUpdate: @Sendable (QuotaSnapshot) async -> Void) async {
        await refresh(ids: [productID], manual: true, onUpdate: onUpdate)
    }
    /// Credential replacement invalidates any response produced using the previous identity.
    public func invalidate(_ productID: String) -> QuotaSnapshot? {
        generation[productID, default: 0] += 1
        retryAfter[productID] = nil
        // A different credential/profile must not inherit another account's healthy values.
        products[productID] = nil
        do { return try publish(at: .now) }
        catch { publicationFailed = true; return nil }
    }
    private func refresh(ids: [String], manual: Bool, onUpdate: @Sendable (QuotaSnapshot) async -> Void) async {
        await withTaskGroup(of: (String, Int, Result<ProductQuota, Error>, Date).self) { group in
            for id in ids {
                guard preferences.isProductEnabled(id), let adapter = adapters[id], !inFlight.contains(id),
                      manual || refreshAfterCredentialChange.contains(id) || preferences.refreshPreference.nextRefresh(after: products[id]?.health?.lastAttempt,
                        minimum: adapter.minimumRefreshInterval, retryAfter: retryAfter[id]) <= .now else { continue }
                refreshAfterCredentialChange.remove(id)
                inFlight.insert(id)
                let version = generation[id, default: 0]
                group.addTask {
                    let now = Date()
                    do {
                        let product = try await adapter.fetchProduct(at: now).validated()
                        guard product.id == id, product.providerID == adapter.descriptor.providerID else { throw ProviderFetchError.invalidResponse }
                        return (id, version, .success(product), now)
                    } catch { return (id, version, .failure(error), now) }
                }
            }
            for await (id, version, result, attempt) in group {
                inFlight.remove(id)
                guard preferences.isProductEnabled(id), generation[id, default: 0] == version else { continue }
                if case .failure(let error) = result, error is CancellationError { continue }
                reconcile(id: id, result: result, attemptedAt: attempt)
                do { await onUpdate(try publish(at: .now)) }
                catch {
                    publicationFailed = true
                    if let canonical = try? publisher.shared.read() { snapshot = canonical; await onUpdate(canonical) }
                }
            }
        }
    }
    private func reconcile(id: String, result: Result<ProductQuota, Error>, attemptedAt: Date) {
        let completedAt = Date()
        switch result {
        case .success(var product):
            if let account = adapters[id] as? CodexAccountAdapter { product.account = account.presentation }
            failures[id] = 0; retryAfter[id] = nil
            product.health = ProviderHealth(state: .healthy, lastAttempt: attemptedAt, lastSuccess: completedAt)
            if let old = products[id] {
                let changed = preferences.providerDisplay != nil ? Self.quotaValuesChanged(old, product) :
                    Self.productChanged(old, product, choice: preferences.preference(product.sourceID).primaryMeterID)
                product.metricChangedAt = changed ? completedAt : old.metricChangedAt
            } else { product.metricChangedAt = completedAt }
            products[id] = product
        case .failure(let error):
            let state = (error as? ProviderFetchError)?.healthState ?? .error
            let count = min(6, failures[id, default: 0] + 1); failures[id] = count
            retryAfter[id] = state == .authenticationRequired ? .distantFuture : completedAt.addingTimeInterval(min(3600, 300 * pow(2, Double(count - 1))))
            let descriptor = adapters[id]!.descriptor
            var product = products[id] ?? ProductQuota(id: id, providerID: descriptor.providerID,
                displayName: descriptor.displayName, meters: [], at: .distantPast)
            if let accountAdapter = adapters[id] as? CodexAccountAdapter { product.account = accountAdapter.presentation }
            let success = product.health?.lastSuccess
            product.health = ProviderHealth(state: success != nil && state != .authenticationRequired ? .stale : state,
                lastAttempt: attemptedAt, lastSuccess: success,
                reason: (error as? ProviderFetchError)?.errorDescription ?? (error as? AccountError)?.errorDescription ?? "Request failed", usingLastKnownGood: success != nil)
            products[id] = product
        }
    }
    private func publish(at date: Date) throws -> QuotaSnapshot {
        let groups = Dictionary(grouping: products.values.filter {
            preferences.isProductEnabled($0.id) && ($0.account == nil || adapters[$0.id] != nil)
        }, by: \.sourceID)
        let providers = groups.map { id, values -> ProviderQuota in
            let ordered = values.sorted { a, b in
                let x = ProviderCatalog.products.firstIndex { $0.id == a.id } ?? Int.max
                let y = ProviderCatalog.products.firstIndex { $0.id == b.id } ?? Int.max
                return x == y ? a.id < b.id : x < y
            }
            var provider = ProviderQuota(id: id, displayName: ProviderCatalog.providers.first { $0.id == id }?.displayName ?? ordered.first?.displayName ?? id, planName: nil, limits: [], lastUpdated: date)
            provider.account = ordered.first?.account
            provider.displayName = ProviderCatalog.providers.first { $0.id == ordered.first?.providerID }?.displayName ?? provider.displayName
            provider.products = ordered
            provider.displayPreference = preferences.preference(id)
            provider = provider.selecting()
            let old = snapshot.providers.first { $0.id == id }
            let selectedChanged = old?.selectedProduct?.id != provider.selectedProduct?.id || old?.primaryMeter?.id != provider.primaryMeter?.id
            if preferences.providerDisplay != nil {
                provider.quotaChangedAt = ordered.filter { $0.meters.contains { $0.kind.drivesAutoHero } }
                    .map(\.metricChangedAt).max() ?? .distantPast
            } else {
                provider.quotaChangedAt = selectedChanged && old != nil && provider.hasMetric ? date :
                    max(provider.selectedProduct?.metricChangedAt ?? .distantPast, old?.quotaChangedAt ?? .distantPast)
            }
            return provider
        }.sorted {
            return ($0.id == "codex" ? "" : $0.id) < ($1.id == "codex" ? "" : $1.id)
        }
        var next = QuotaSnapshot(generatedAt: date, providers: providers)
        next.heroSelection = snapshot.heroSelection.followingCodexLogin; next.platformPreferences = preferences
        try publisher.publish(next); snapshot = next; publicationFailed = false
        return next
    }
    public func markStale(now: Date = .now) throws -> QuotaSnapshot? {
        var changed = false
        for id in products.keys {
            guard let health = products[id]?.health, health.state == .healthy,
                  let success = health.lastSuccess, now.timeIntervalSince(success) >= Self.freshnessThreshold else { continue }
            products[id]?.health?.state = .stale; products[id]?.health?.usingLastKnownGood = true
            products[id]?.health?.reason = "Last update is old"; changed = true
        }
        return changed ? try publish(at: now) : nil
    }
    public static func productChanged(_ old: ProductQuota, _ new: ProductQuota, choice: String?) -> Bool {
        let a = old.primary(choice), b = new.primary(choice)
        if a?.id != b?.id || a?.kind != b?.kind || a?.value != b?.value || a?.currency != b?.currency { return true }
        // Preserve subscription window changes; unrelated usage and balance breakdown never steal Hero.
        let oldQuotas = old.meters.filter { $0.kind == .percentageQuota || $0.kind == .absoluteQuota || $0.kind == .credits }
        let newQuotas = new.meters.filter { $0.kind == .percentageQuota || $0.kind == .absoluteQuota || $0.kind == .credits }
        guard oldQuotas.count == newQuotas.count, old.bankResetCount == new.bankResetCount else { return true }
        for meter in newQuotas {
            guard let previous = oldQuotas.first(where: { $0.id == meter.id }), previous.value == meter.value,
                  previous.displayName == meter.displayName, previous.total == meter.total else { return true }
            switch (previous.resetAt, meter.resetAt) {
            case (nil, nil): break
            case let (x?, y?) where abs(x.timeIntervalSince(y)) <= 60: break
            default: return true
            }
        }
        return false
    }
    /// A polling timestamp, health update, reset countdown, usage statistic or
    /// renamed meter must not look like someone used quota on that provider.
    public static func quotaValuesChanged(_ old: ProductQuota, _ new: ProductQuota) -> Bool {
        let before = old.meters.filter { $0.kind.drivesAutoHero }
        let after = new.meters.filter { $0.kind.drivesAutoHero }
        guard before.count == after.count else { return true }
        return after.contains { meter in
            guard let previous = before.first(where: { $0.id == meter.id }) else { return true }
            return previous.kind != meter.kind || previous.value != meter.value || previous.total != meter.total ||
                previous.remaining != meter.remaining || previous.currency != meter.currency
        }
    }
    public static func quotaChanged(_ old: ProviderQuota, _ new: ProviderQuota) -> Bool {
        productChanged(ProductMigration.product(old), ProductMigration.product(new), choice: nil)
    }
}
