import Foundation

public enum OnboardingStep: Int, CaseIterable, Codable, Sendable {
    // Keep persisted v1 identifiers stable when inserting the appearance page.
    case welcome = 0, appearance = 4, connection = 1, display = 2, ready = 3
    public var position: Int { Self.allCases.firstIndex(of: self)! }
    public func offset(by amount: Int) -> Self? {
        let index = position + amount
        return Self.allCases.indices.contains(index) ? Self.allCases[index] : nil
    }
}

/// Finishing the tour does not assert that any provider is connected or healthy.
public struct OnboardingProgress: Codable, Equatable, Sendable {
    public enum Disposition: String, Codable, Sendable { case inProgress, deferred, completed }
    public private(set) var step: OnboardingStep = .welcome
    public private(set) var disposition: Disposition = .inProgress
    public private(set) var completedAt: Date?
    public var shouldPresentAutomatically: Bool { disposition == .inProgress }
    public init() {}
    public mutating func move(to step: OnboardingStep) { self.step = step }
    public mutating func finish(at date: Date = Date()) {
        disposition = .completed; completedAt = completedAt ?? date
    }
    public mutating func deferSetup() {
        // Reopening a completed tour must never erase its first completion.
        if completedAt == nil { disposition = .deferred }
    }
    public static func load(defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: "onboarding.v1"),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return value
    }
    public func save(defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(self), forKey: "onboarding.v1")
    }
}

public enum OnboardingReadiness {
    /// A stored connection or an old number alone is not evidence of live data.
    public static func usable(_ provider: ProviderQuota) -> Bool {
        provider.activeProducts.contains { product in
            (product.health ?? provider.health)?.state == .healthy && !product.meters.isEmpty
        }
    }
}
