import SwiftUI
import QuotaCore

enum ProviderCardDensity { case compact, medium, full, menuHero, ambientHero, ambientRail }
private enum CardComposition { case compact, medium, full }

enum ProviderCardTokens {
    static let ink = Color(red: 0.95, green: 0.95, blue: 0.92)
    static let muted = Color(red: 0.70, green: 0.71, blue: 0.70)
    static let accent = Color(red: 0.80, green: 0.82, blue: 0.77)
    static let panel = Color(red: 0.15, green: 0.16, blue: 0.17)
    static let rule = Color.white.opacity(0.19)
    static let radius: CGFloat = 22
    static let label = Font.system(size: 9, weight: .semibold, design: .rounded)
    static func title(_ density: ProviderCardDensity, scale: CGFloat, language: AppLanguage = .english) -> Font {
        .system(size: (density == .compact ? 14 : density == .medium || density == .menuHero || density == .ambientRail ? 14 : 31) * scale,
                weight: .regular, design: .serif)
    }
    static func metric(_ density: ProviderCardDensity, scale: CGFloat, oneWindow: Bool, language: AppLanguage = .english) -> Font {
        .system(size: (density == .compact ? 48 : density == .medium || density == .menuHero || density == .ambientRail ? 50 : oneWindow ? 104 : 84) * scale,
                weight: .regular, design: .serif)
    }
}

/// Shared dark glass treatment for the app and screen saver; WidgetKit supplies its own host background.
struct GlassCardBackground: View {
    var radius: CGFloat = ProviderCardTokens.radius
    var readabilityShade: Double = 0
    var saverPanel = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if reduceTransparency {
            shape.fill(Color(red: 0.13, green: 0.14, blue: 0.15))
        } else if #available(macOS 26.0, *) {
            shape.fill(Color.clear)
                .glassEffect(saverPanel ? .clear.tint(Color.black.opacity(0.12)) : .regular.tint(Color.black.opacity(0.22)), in: shape)
                .background(shape.fill(saverPanel ? Color(white: 0.035) : Color.clear))
                .overlay(shape.fill(Color.black.opacity(readabilityShade)))
                .overlay {
                    if saverPanel {
                        // A broad, low-contrast inner bevel suggests thickness without a white halo.
                        shape.strokeBorder(LinearGradient(stops: [
                            .init(color: .white.opacity(0.10), location: 0),
                            .init(color: .white.opacity(0.025), location: 0.22),
                            .init(color: .black.opacity(0.20), location: 0.56),
                            .init(color: .white.opacity(0.06), location: 1)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: radius * 0.30)
                        .blur(radius: radius * 0.07).clipShape(shape)
                    }
                }
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(saverPanel ? 0.16 : 0.24), .white.opacity(saverPanel ? 0.025 : 0.04), .white.opacity(saverPanel ? 0.08 : 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: saverPanel ? max(0.6, radius / 80) : 0.7))
        } else {
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(Color.black.opacity(0.57)))
                .overlay(shape.fill(Color.black.opacity(readabilityShade)))
                .clipShape(shape)
        }
    }
}

/// One content family shared by Widget, Menu Bar and Screen Saver. Surfaces supply only frame and scale.
struct ProviderCard: View {
    let provider: ProviderQuota?
    let density: ProviderCardDensity
    var drawsPanel = true
    var panelReadabilityShade: Double = 0
    var saverPanel = false
    var language: AppLanguage = .english
    var layoutScale: CGFloat = 1
    var usesSystemTint = false
    private var ink: Color { usesSystemTint ? .primary : ProviderCardTokens.ink }
    private var muted: Color { usesSystemTint ? .primary.opacity(0.72) : ProviderCardTokens.muted }
    private var rule: Color { usesSystemTint ? .primary.opacity(0.22) : ProviderCardTokens.rule }
    private var accent: Color { usesSystemTint ? .primary : ProviderCardTokens.accent }
    private var track: Color { usesSystemTint ? .primary.opacity(0.18) : .white.opacity(0.13) }
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var composition: CardComposition {
        switch density {
        case .compact: .compact
        case .medium, .menuHero, .ambientRail: .medium
        case .full, .ambientHero: .full
        }
    }
    private func s(_ value: CGFloat) -> CGFloat { value * layoutScale }
    private func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: s(size), weight: weight, design: .default)
    }
    private func editorial(_ size: CGFloat, text: String, weight: Font.Weight = .regular) -> Font {
        let hasHan = text.unicodeScalars.contains { (0x3040...0x9FFF).contains(Int($0.value)) || (0xAC00...0xD7AF).contains(Int($0.value)) }
        return .system(size: s(size), weight: weight, design: hasHan ? .default : .serif)
    }
    private var primary: LimitWindow? { provider?.primaryLimit }
    private var balance: BalanceAmount? { provider?.primaryBalance }
    private var secondary: LimitWindow? { provider?.limits.first { $0.id != primary?.id } }
    private var progressLimit: LimitWindow? { secondary ?? primary }
    private var showsSecondaryProgress: Bool { secondary != nil }
    private var metric: String? {
        if provider?.products != nil { return provider?.primaryMeter?.formattedValue }
        if let primary { return QuotaFormat.percentage(primary.remainingPercentage) }
        if let balance { return balance.formatted(balance.total) }
        return nil
    }
    private var supportingMeters: [Meter] {
        guard let product = provider?.selectedProduct, let primary = provider?.primaryMeter,
              primary.kind == .usage || primary.kind == .spend || primary.kind == .credits else { return [] }
        return product.meters.filter { $0.id != primary.id && $0.primaryEligible }
    }
    private var wideBalance: Bool { balance != nil && (metric?.count ?? 0) > 8 }

    private var title: String { provider?.displayName ?? "QuotaClock" }
    private var primaryLabel: String {
        guard let meter = provider?.primaryMeter else { return AppText.value(balance == nil ? "Remaining" : "Balance", language) }
        return AppText.value(meter.kind == .usage || meter.kind == .spend ? meter.displayName : meter.label, language)
    }
    private var resetLabel: String {
        guard let primary else { return "" }
        let key = primary.windowDuration == 18_000 || primary.id.lowercased().contains("5h") ? "5H RESET" :
            primary.windowDuration == 604_800 || primary.displayName.lowercased().contains("week") ? "WEEK RESET" : "RESET"
        return AppText.value(key, language)
    }
    private func resetTime(compact: Bool) -> String {
        guard let date = primary?.resetAt else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.timeZone = .current
        formatter.dateFormat = compact ? "HH:mm" : "MM/dd HH:mm"
        return formatter.string(from: date)
    }
    private var statusCopy: String {
        guard let primary else { return "" }
        let text = primary.remainingPercentage >= 60 ? "Plenty of limit remains." :
            primary.remainingPercentage >= 30 ? "Keep an eye on pace. You still have room to work." :
            "Slow the pace. Your limit is getting close."
        return AppText.value(text, language)
    }
    private func compactCount(_ value: Int64) -> String {
        let magnitude = abs(Double(value))
        let divisor: Double = magnitude >= 1_000_000_000 ? 1_000_000_000 : magnitude >= 1_000_000 ? 1_000_000 : magnitude >= 1_000 ? 1_000 : 1
        let suffix = divisor == 1_000_000_000 ? "B" : divisor == 1_000_000 ? "M" : divisor == 1_000 ? "K" : ""
        guard divisor > 1 else { return value.formatted() }
        return String(format: divisor == 1_000_000_000 ? "%.2f%@" : "%.1f%@", Double(value) / divisor, suffix)
    }

    var body: some View {
        Group {
            if provider?.id == "deepseek", metric != nil {
                deepSeekContent
            } else { switch composition {
            case .compact: compactContent
            case .medium: mediumContent
            case .full: fullContent
            } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(ink)
        .background {
            if drawsPanel {
                GlassCardBackground(radius: s(ProviderCardTokens.radius),
                                    readabilityShade: panelReadabilityShade, saverPanel: saverPanel)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: s(ProviderCardTokens.radius)))
        .accessibilityElement(children: .combine)
    }

    private func header(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: s(3)) {
        HStack(alignment: .top, spacing: s(6)) {
            ProviderAccountHeader(provider: provider, titleSize: composition == .full ? 31 : 14, scale: layoutScale)
            Spacer(minLength: s(2))
            if primary?.resetAt != nil && !compact {
                if density == .medium || density == .menuHero || density == .ambientRail {
                    HStack(alignment: .firstTextBaseline, spacing: s(5)) {
                        Text(resetLabel).font(sans(7.5, weight: .semibold)).tracking(s(0.3))
                        Text(resetTime(compact: false)).font(editorial(13, text: resetTime(compact: false)))
                    }.foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    VStack(alignment: .trailing, spacing: s(2)) {
                        Text(resetLabel).font(sans(13, weight: .semibold)).tracking(s(0.8))
                        Text(resetTime(compact: false)).font(editorial(22, text: resetTime(compact: false)))
                    }.foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.72)
                }
            }
        }
        if compact, primary?.resetAt != nil {
            Text(resetLabel + "  " + resetTime(compact: false))
                .font(sans(8, weight: .medium)).foregroundStyle(muted)
                .lineLimit(1).minimumScaleFactor(0.8).monospacedDigit()
        }
        }
    }
    private func metricBlock(_ size: ProviderCardDensity) -> some View {
        VStack(alignment: .leading, spacing: s(-3)) {
            if let metric, size == .compact, primary != nil {
                Text(metric).font(.system(size: s(52), weight: .regular, design: .serif))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(height: s(52), alignment: .leading)
                    .contentTransition(.numericText())
                Text(primaryLabel).font(editorial(16, text: primaryLabel))
                    .foregroundStyle(muted)
                    .lineLimit(1).minimumScaleFactor(0.65)
                    .frame(height: s(18), alignment: .leading)
            } else if let metric {
                Text(metric).font(ProviderCardTokens.metric(size, scale: layoutScale, oneWindow: secondary == nil, language: language)).lineLimit(1)
                    .minimumScaleFactor(metric.count > 8 ? 0.25 : 0.48)
                    .contentTransition(.numericText())
                Text(primaryLabel).font(editorial(size == .compact ? 20 : size == .full || size == .ambientHero ? (secondary == nil ? 38 : 32) : 15, text: primaryLabel))
                    .foregroundStyle(muted)
                    .lineLimit(1).minimumScaleFactor(0.65)
            } else {
                let message = AppText.value(provider?.health?.state == .authenticationRequired ? "Authentication required" : "No data yet", language)
                Text(message)
                    .font(editorial(size == .compact ? 17 : 23, text: message))
                    .lineLimit(2).minimumScaleFactor(0.7)
                if let reason = provider?.health?.reason {
                    Text(AppText.value(reason, language)).font(sans(10)).foregroundStyle(muted).lineLimit(1)
                }
            }

        }
    }
    private func metadata(_ label: String, _ value: String, small: Bool = false,
                          labelSize: CGFloat? = nil, valueSize: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: s(density == .compact && showsSecondaryProgress ? 4 : 2)) {
            Text(AppText.value(label, language)).font(sans(labelSize ?? (small ? 9 : 12), weight: .semibold)).tracking(s(0.6))
                .foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.72)
            Text(AppText.value(value, language)).font(editorial(valueSize ?? (small ? 15 : 20), text: AppText.value(value, language)))
                .lineLimit(1).minimumScaleFactor(0.72)
        }
    }
    private func mediumStatRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: s(8)) {
            Text(AppText.value(label, language)).font(sans(11, weight: .semibold))
                .foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: s(8))
            Text(AppText.value(value, language)).font(editorial(12, text: AppText.value(value, language)))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }
    private func progressBar(_ value: Double, height: CGFloat) -> some View {
        GeometryReader { bounds in
            Capsule().fill(track)
                .overlay(alignment: .leading) {
                    Capsule().fill(accent)
                        .frame(width: max(0, bounds.size.width * min(100, max(0, value)) / 100))
                }
        }.frame(height: s(height))
    }
    private func limitRow(compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: s(compact ? 4 : 6)) {
            if let limit = progressLimit {
                HStack(alignment: .firstTextBaseline, spacing: s(3)) {
                    Text(AppText.value(limit.displayName.uppercased() + (compact ? "" : " LIMIT"), language))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: s(3))
                    Text(QuotaFormat.percentage(limit.remainingPercentage) + (compact ? "" : " " + AppText.value("Remaining", language)))
                        .font(sans(compact ? 9 : 10, weight: .semibold))
                }.font(sans(compact ? 9 : 10, weight: .semibold)).tracking(s(0.5)).foregroundStyle(muted)
                progressBar(limit.remainingPercentage, height: compact ? 6 : density == .medium || density == .ambientRail ? 10 : 8)
            }
        }
    }
    private var todayTokensText: String {
        todayMeter("local.today.tokens").map { compactCount(NSDecimalNumber(decimal: $0.value).int64Value) } ?? "—"
    }
    private var todayCostText: String {
        todayMeter("local.today.cny").map { $0.formattedValue } ?? "—"
    }
    private var deepSeekContent: some View {
        let compact = composition == .compact
        let full = composition == .full
        return VStack(alignment: .leading, spacing: s(full ? 10 : 2)) {
            header(compact: compact)
            Spacer(minLength: 0)
            Text(metric ?? "—")
                .font(.system(size: s(compact ? 34 : full ? 72 : 42), design: .serif))
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(primaryLabel).font(editorial(compact ? 16 : full ? 26 : 17, text: primaryLabel))
                .foregroundStyle(muted)
            Spacer(minLength: 0)
            Color.clear.frame(height: s(0.5))
            Text(AppText.value("Usage Today · DSH", language))
                .font(sans(compact ? 8 : full ? 11 : 9, weight: .semibold))
                .foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.7)
            HStack(alignment: .top, spacing: s(compact ? 8 : 24)) {
                metadata("Tokens", todayTokensText, small: true, labelSize: compact ? 7 : full ? 10 : 8, valueSize: compact ? 13 : full ? 28 : 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                metadata("Estimated CNY", todayCostText, small: true, labelSize: compact ? 7 : full ? 10 : 8, valueSize: compact ? 13 : full ? 28 : 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if full, let balance, balance.toppedUp != nil || balance.granted != nil {
                Color.clear.frame(height: s(12.5))
                HStack(spacing: s(24)) {
                    if let topped = balance.toppedUp { metadata("TOPPED UP", balance.formatted(topped)).frame(maxWidth: .infinity, alignment: .leading) }
                    if let granted = balance.granted { metadata("GRANTED", balance.formatted(granted)).frame(maxWidth: .infinity, alignment: .leading) }
                }
            }
        }.padding(s(compact ? 14 : full ? 20 : 12))
            .help(AppText.value("Local DSH records only; not account-wide billing. Missing records are not zero usage.", language))
    }
    private var compactContent: some View {
        VStack(alignment: .leading, spacing: s(showsSecondaryProgress ? 2 : 7)) {
            header(compact: true)
            Spacer(minLength: 0)
            metricBlock(.compact).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if showsSecondaryProgress { limitRow(compact: true) }
            if let support = supportingMeters.first { metadata(support.displayName, support.formattedValue, small: true) }
            if provider?.bankResetCount != nil || provider?.planName != nil {
                HStack(alignment: .top, spacing: s(10)) {
                    if let count = provider?.bankResetCount { metadata("BANK RESET", "\(count)", small: true, labelSize: showsSecondaryProgress ? 8 : 9, valueSize: showsSecondaryProgress ? 13 : 15) }
                    if provider?.bankResetCount != nil && provider?.planName != nil {
                        Rectangle().fill(rule).frame(width: s(1), height: s(showsSecondaryProgress ? 27 : 28))
                    }
                    if let plan = provider?.planName { metadata("PLAN", plan, small: true, labelSize: showsSecondaryProgress ? 8 : 9, valueSize: showsSecondaryProgress ? 13 : 15) }
                }.padding(.top, s(showsSecondaryProgress ? 5 : 0))
            }
        }.padding(.horizontal, s(14)).padding(.vertical, s(showsSecondaryProgress ? 10 : 14))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var mediumContent: some View {
        VStack(alignment: .leading, spacing: s(3)) {
            header(compact: false)
            if metric == nil {
                metricBlock(.medium).frame(maxWidth: .infinity, alignment: .leading)
            } else if wideBalance {
                metricBlock(.medium).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: s(12)) {
                    metricBlock(.medium).frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(rule).frame(width: s(1), height: s(63))
                    VStack(alignment: .leading, spacing: s(4)) {
                        if let plan = provider?.planName { mediumStatRow("PLAN", plan) }
                        if provider?.bankResetCount != nil || provider?.usage != nil {
                            mediumStatRow("BANK RESET", provider?.bankResetCount.map(String.init) ?? "--")
                            mediumStatRow("LAST DAY", provider?.usage?.lastDailyTokens.map(compactCount) ?? "--")
                        } else if let available = provider?.balanceAvailable {
                            mediumStatRow("AVAILABLE", available ? "Yes" : "No")
                        } else if !supportingMeters.isEmpty {
                            ForEach(Array(supportingMeters.prefix(3))) { meter in
                                mediumStatRow(meter.displayName, meter.formattedValue)
                            }
                        } else if let product = provider?.selectedProduct {
                            mediumStatRow("Products", product.displayName)
                            if let unit = provider?.primaryMeter?.unit { mediumStatRow("Usage", unit) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, s(4))
            }
            if progressLimit != nil {
                limitRow().padding(.top, s(3)).offset(y: density == .medium ? 2 : 0)
            } else if let balance {
                if provider?.id == "deepseek" { todayUsage } else { HStack(spacing: s(16)) {
                    if let topped = balance.toppedUp { metadata("TOPPED UP", balance.formatted(topped), small: true, valueSize: 12) }
                    if let granted = balance.granted { metadata("GRANTED", balance.formatted(granted), small: true, valueSize: 12) }
                } }
            }
        }.padding(.horizontal, s(12)).padding(.top, s(16)).padding(.bottom, s(8))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func todayMeter(_ id: String) -> Meter? {
        provider?.selectedProduct?.meters.first { $0.id == id && ($0.resetAt ?? .distantPast) > Date() }
    }
    private var todayUsage: some View {
        HStack(alignment: .top, spacing: s(16)) {
            metadata("Usage Today · DSH", todayMeter("local.today.tokens").map { compactCount(NSDecimalNumber(decimal: $0.value).int64Value) + " tokens" } ?? "—", small: true, valueSize: 12)
            metadata("Estimated CNY · DSH", todayMeter("local.today.cny").map { "≈" + $0.formattedValue } ?? "—", small: true, valueSize: 12)
        }.help(AppText.value("Local DSH records only; not account-wide billing. Missing records are not zero usage.", language))
    }
    private var fullContent: some View {
        VStack(alignment: .leading, spacing: s(8)) {
            header(compact: false)
            Spacer(minLength: 0)
            if metric == nil {
                metricBlock(.full).frame(maxWidth: s(230), alignment: .leading)
            } else if wideBalance || (primary == nil && provider?.planName == nil && provider?.balanceAvailable == nil) {
                metricBlock(.full).frame(maxWidth: .infinity, alignment: .leading)
                if let available = provider?.balanceAvailable { metadata("AVAILABLE", available ? "Yes" : "No") }
            } else {
                GeometryReader { available in
                    let leftWidth = min(s(176), max(s(146), available.size.width * 0.5))
                    HStack(alignment: .top, spacing: s(12)) {
                        metricBlock(.full).frame(width: leftWidth, alignment: .leading).layoutPriority(1)
                        Rectangle().fill(rule).frame(width: s(1), height: s(secondary == nil ? 106 : 94))
                        VStack(alignment: .leading, spacing: s(7)) {
                            if let plan = provider?.planName { metadata("PLAN", plan, labelSize: 10, valueSize: 24) }
                            if let available = provider?.balanceAvailable { metadata("AVAILABLE", available ? "Yes" : "No") }
                            if primary != nil {
                                Text(statusCopy).font(editorial(13, text: statusCopy)).italic()
                                    .foregroundStyle(muted).lineLimit(4)
                                    .minimumScaleFactor(0.82)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, s(6))
                    }
                }.frame(height: s(secondary == nil ? 132 : 112))
            }
            if showsSecondaryProgress {
                limitRow()
            }
            Spacer(minLength: 0)
            if provider?.id == "deepseek" { todayUsage }
            if let balance, primary == nil {
                HStack(spacing: s(16)) {
                    if let topped = balance.toppedUp { metadata("TOPPED UP", balance.formatted(topped)) }
                    if let granted = balance.granted { metadata("GRANTED", balance.formatted(granted)) }
                }
            } else {
                fullStats
            }
            if !supportingMeters.isEmpty {
                HStack(alignment: .top, spacing: s(12)) {
                    ForEach(Array(supportingMeters.prefix(3))) { meter in
                        metadata(meter.displayName, meter.formattedValue, small: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else if primary == nil && balance == nil, let meter = provider?.primaryMeter {
                metadata(meter.displayName, meter.unit ?? meter.label)
            }
            if let products = provider?.products, products.count > 1,
               let other = products.first(where: { $0.id != provider?.selectedProduct?.id && $0.primary() != nil }), let meter = other.primary() {
                mediumStatRow(other.displayName, meter.formattedValue)
            }
        }.padding(s(20)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    @ViewBuilder private var fullStats: some View {
        let days = provider?.usage?.dailyHistory ?? []
        if primary != nil && (provider?.bankResetCount != nil || provider?.usage != nil) {
            HStack(alignment: .top, spacing: s(12)) {
                VStack(alignment: .leading, spacing: s(secondary == nil ? 17 : 12)) {
                    metadata("BANK RESET", provider?.bankResetCount.map(String.init) ?? "--")
                    metadata("PEAK DAY", provider?.usage?.peakDailyTokens.map(compactCount) ??
                        days.map(\.tokens).max().map(compactCount) ?? "--")
                }.frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(rule).frame(width: s(1), height: s(secondary == nil ? 108 : 92))
                VStack(alignment: .leading, spacing: s(secondary == nil ? 17 : 12)) {
                    metadata("TOTAL TOKENS", provider?.usage?.totalTokens.map(compactCount) ?? "--")
                    metadata("LAST DAY", provider?.usage?.lastDailyTokens.map(compactCount) ??
                        days.last.map { compactCount($0.tokens) } ?? "--")
                }.frame(maxWidth: .infinity, alignment: .leading)
                sevenDayChart(days)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }
    private func sevenDayChart(_ days: [UsageDay]) -> some View {
        let visibleDays = Array(days.sorted { $0.date < $1.date }.suffix(7))
        let maximum = max(1, visibleDays.map(\.tokens).max() ?? 1)
        return VStack(alignment: .leading, spacing: s(5)) {
            Text(AppText.value("7D TOKENS", language)).font(sans(10, weight: .semibold))
                .foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.7)
            Text(days.isEmpty ? "--" : "MAX " + compactCount(maximum))
                .font(sans(8)).foregroundStyle(muted)
            if days.isEmpty {
                Text(AppText.value("No history", language))
                    .font(sans(10)).foregroundStyle(muted)
                    .frame(height: s(62), alignment: .center)
            } else {
                GeometryReader { graph in
                    ZStack(alignment: .bottom) {
                        VStack {
                            Rectangle().fill(rule.opacity(0.65)).frame(height: s(0.5))
                            Spacer()
                            Rectangle().fill(rule.opacity(0.65)).frame(height: s(0.5))
                            Spacer()
                            Rectangle().fill(rule).frame(height: s(0.5))
                        }
                        HStack(alignment: .bottom, spacing: s(3)) {
                            ForEach(0..<(7 - visibleDays.count), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity)
                            }
                            ForEach(Array(visibleDays.enumerated()), id: \.offset) { index, day in
                                RoundedRectangle(cornerRadius: s(1.5))
                                    .fill(ink.opacity(index == visibleDays.count - 1 ? 0.8 : 0.48))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: max(s(2), graph.size.height * CGFloat(day.tokens) / CGFloat(maximum)))
                            }
                        }
                    }
                }.frame(height: s(secondary == nil ? 62 : 48))
                HStack {
                    if visibleDays.count > 1 { Text(dayLabel(visibleDays.first!.date)) }
                    Spacer(minLength: 0)
                    Text(dayLabel(visibleDays.last!.date))
                }.font(sans(8)).foregroundStyle(muted)
            }
        }
    }
}
