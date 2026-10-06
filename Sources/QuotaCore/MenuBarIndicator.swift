import Foundation

/// Pure presentation of the same selected Product/Meter used by the menu card.
public struct MenuBarIndicator: Equatable, Sendable {
    public let text: String
    public let fraction: Double?
    public let providerName: String
    public let providerID: String?
    public let isStale: Bool
    public init(snapshot: QuotaSnapshot?) {
        let visible = snapshot?.forSurface(.menuBar)
        let provider = snapshot?.platformPreferences?.providerDisplay != nil || snapshot?.platformPreferences?.surfaces != nil ? visible?.providers.first :
            (visible?.hero ?? visible?.providers.first { $0.displayPreference?.heroEligible ?? true })
        providerID = provider?.baseProviderID
        providerName = provider?.sourceTitle ?? "QuotaClock"
        isStale = provider?.health?.usingLastKnownGood == true || provider?.health?.state == .stale
        guard let meter = provider?.primaryMeter else { text = "—"; fraction = nil; return }
        if meter.kind == .percentageQuota {
            let value = NSDecimalNumber(decimal: meter.value).doubleValue
            fraction = min(1, max(0, value / 100))
            text = QuotaFormat.percentage(value)
        } else { text = meter.formattedValue; fraction = nil }
    }
}
