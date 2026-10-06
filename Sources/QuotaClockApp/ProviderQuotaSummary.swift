import SwiftUI
import QuotaCore

/// Connection settings show every enabled product's figures, independently of
/// the metric selected for the Hero or other display surfaces.
struct ProviderQuotaSummary: View {
    let provider: ProviderQuota?
    let enabled: Bool
    let language: AppLanguage
    private func t(_ key: String) -> String { AppText.value(key, language) }
    private var products: [ProductQuota] { enabled ? provider?.activeProducts ?? [] : [] }
    private var hasMultipleMeters: Bool { products.contains { $0.meters.filter(\.primaryEligible).count > 1 } }
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !enabled {
                Text(t("Disabled")).font(.caption).foregroundStyle(.secondary)
            } else if products.isEmpty {
                Text(t(provider?.health?.state.displayName ?? "Waiting")).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(products) { product in
                    let meters = product.meters.filter(\.primaryEligible)
                    let health = product.health ?? provider?.health
                    VStack(alignment: .trailing, spacing: 4) {
                        if products.count > 1 {
                            Text(t(product.displayName)).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        if !meters.isEmpty {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .trailing), count: min(meters.count, 2)),
                                      alignment: .trailing, spacing: 6) {
                                ForEach(meters) { meter in
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(label(meter)).font(.system(size: 10)).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(meter.formattedValue).font(.system(size: 17, weight: .regular, design: .serif)).monospacedDigit()
                                            .lineLimit(1).minimumScaleFactor(0.8)
                                    }.accessibilityElement(children: .combine)
                                }
                            }
                        }
                        if meters.isEmpty || health?.state != .healthy {
                            Text(t(health?.state.displayName ?? "Waiting"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.frame(width: hasMultipleMeters ? 190 : 125, alignment: .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
    }
    private var accessibilitySummary: String {
        guard enabled else { return t("Disabled") }
        guard !products.isEmpty else { return t(provider?.health?.state.displayName ?? "Waiting") }
        return products.map { product in
            let meters = product.meters.filter(\.primaryEligible)
            var parts = products.count > 1 ? [t(product.displayName)] : []
            parts += meters.map { label($0) + " " + $0.formattedValue }
            let health = product.health ?? provider?.health
            if meters.isEmpty || health?.state != .healthy {
                parts.append(t(health?.state.displayName ?? "Waiting"))
            }
            return parts.joined(separator: ", ")
        }.joined(separator: "; ")
    }
    private func label(_ meter: Meter) -> String {
        switch meter.kind {
        case .percentageQuota, .absoluteQuota:
            switch meter.displayName {
            case "5-hour": return t("5h Remaining")
            case "Weekly": return t("Weekly Remaining")
            default: return t(meter.displayName) + " · " + t("Remaining")
            }
        default: return t(meter.label)
        }
    }
}

/// Keep reset dates in the expanded controls without repeating quota values.
struct ProviderResetTimes: View {
    let provider: ProviderQuota?
    let language: AppLanguage
    private func t(_ key: String) -> String { AppText.value(key, language) }
    private var products: [ProductQuota] {
        (provider?.activeProducts ?? []).filter { $0.meters.contains { $0.resetAt != nil } }
    }
    var body: some View {
        if !products.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(t("Next reset time"))
                ForEach(products) { product in
                    if products.count > 1 { Text(t(product.displayName)) }
                    ForEach(product.meters.filter { $0.resetAt != nil }) { meter in
                        if let reset = meter.resetAt {
                            Text(t(meter.displayName) + " · " + reset.formatted())
                        }
                    }
                }
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}
