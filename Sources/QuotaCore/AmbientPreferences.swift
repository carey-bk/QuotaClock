import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case english, chinese, traditionalChinese, japanese, korean, french
    public var nativeName: String {
        switch self {
        case .english: "English"
        case .chinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .french: "Français"
        }
    }
    public var localeIdentifier: String {
        switch self {
        case .english: "en_US"
        case .chinese: "zh_CN"
        case .traditionalChinese: "zh_TW"
        case .japanese: "ja_JP"
        case .korean: "ko_KR"
        case .french: "fr_FR"
        }
    }
}
public enum AppAppearance: String, Codable, CaseIterable, Sendable { case system, dark, light }
public enum AmbientTimeFormat: String, Codable, CaseIterable, Sendable { case automatic, twentyFourHour, twelveHour }
public enum SurfaceLanguageSelection: String, Codable, CaseIterable, Sendable {
    case defaultEnglish, appLanguage, english, chinese, traditionalChinese, japanese, korean, french
    public var fixedLanguage: AppLanguage? {
        switch self {
        case .defaultEnglish, .english: .english
        case .appLanguage: nil
        case .chinese: .chinese
        case .traditionalChinese: .traditionalChinese
        case .japanese: .japanese
        case .korean: .korean
        case .french: .french
        }
    }
    public func resolved(appLanguage: AppLanguage) -> AppLanguage { fixedLanguage ?? appLanguage }
}
public struct AmbientPreferences: Codable, Equatable, Sendable {
    /// Settings-window language. Presentation surfaces have independent choices.
    public var language: AppLanguage = .english
    public var useAppLanguageForSurfaces = false
    /// Nil retains older independent per-surface choices until the user makes a selection.
    public var surfaceLanguageSelection: SurfaceLanguageSelection? = .defaultEnglish
    public var appearance: AppAppearance = .system
    public var effectiveWidgetLanguage: AppLanguage { surfaceLanguageSelection?.resolved(appLanguage: language) ?? (useAppLanguageForSurfaces ? language : widgetLanguage) }
    public var effectiveMenuLanguage: AppLanguage { surfaceLanguageSelection?.resolved(appLanguage: language) ?? (useAppLanguageForSurfaces ? language : menuLanguage) }
    public var effectiveSaverLanguage: AppLanguage { surfaceLanguageSelection?.resolved(appLanguage: language) ?? (useAppLanguageForSurfaces ? language : saverLanguage) }
    public var displayedSurfaceLanguageSelection: SurfaceLanguageSelection? {
        if let surfaceLanguageSelection { return surfaceLanguageSelection }
        if useAppLanguageForSurfaces { return .appLanguage }
        guard widgetLanguage == menuLanguage, menuLanguage == saverLanguage else { return nil }
        return widgetLanguage == .english ? .defaultEnglish : SurfaceLanguageSelection(rawValue: widgetLanguage.rawValue)
    }
    public mutating func selectSurfaceLanguage(_ selection: SurfaceLanguageSelection) {
        surfaceLanguageSelection = selection
        // Keep older readers compatible without discarding the previous fixed language when following the app.
        useAppLanguageForSurfaces = selection == .appLanguage
        if let fixed = selection.fixedLanguage {
            widgetLanguage = fixed; menuLanguage = fixed; saverLanguage = fixed
        }
    }
    public var followsAppLanguage: Bool {
        surfaceLanguageSelection == .appLanguage || (surfaceLanguageSelection == nil && useAppLanguageForSurfaces)
    }
    public mutating func setFollowAppLanguage(_ follow: Bool) {
        if follow && !followsAppLanguage {
            widgetLanguage = effectiveWidgetLanguage
            menuLanguage = effectiveMenuLanguage
            saverLanguage = effectiveSaverLanguage
        }
        surfaceLanguageSelection = follow ? .appLanguage : nil
        useAppLanguageForSurfaces = follow
    }
    public mutating func setLanguage(_ value: AppLanguage, for surface: DisplaySurface) {
        if !followsAppLanguage {
            widgetLanguage = effectiveWidgetLanguage
            menuLanguage = effectiveMenuLanguage
            saverLanguage = effectiveSaverLanguage
        }
        surfaceLanguageSelection = nil
        useAppLanguageForSurfaces = false
        switch surface { case .widget: widgetLanguage = value; case .menuBar: menuLanguage = value; case .screenSaver: saverLanguage = value }
    }
    public var widgetLanguage: AppLanguage = .english
    public var menuLanguage: AppLanguage = .english
    public var saverLanguage: AppLanguage = .english
    public var showClock = true
    public var showDate = true
    public var timeFormat: AmbientTimeFormat = .automatic
    public var showAMPM = true
    public var pageDuration = 20
    public var burnInProtection = true
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case language, widgetLanguage, menuLanguage, saverLanguage, useAppLanguageForSurfaces, surfaceLanguageSelection, appearance
        case showClock, showDate, timeFormat, showAMPM, pageDuration, burnInProtection
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try values.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
        useAppLanguageForSurfaces = try values.decodeIfPresent(Bool.self, forKey: .useAppLanguageForSurfaces) ?? false
        surfaceLanguageSelection = try values.decodeIfPresent(SurfaceLanguageSelection.self, forKey: .surfaceLanguageSelection)
        language = try values.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .english
        // Older files had one language for every surface. New independent
        // choices intentionally start in English without changing Settings.
        widgetLanguage = try values.decodeIfPresent(AppLanguage.self, forKey: .widgetLanguage) ?? .english
        menuLanguage = try values.decodeIfPresent(AppLanguage.self, forKey: .menuLanguage) ?? .english
        saverLanguage = try values.decodeIfPresent(AppLanguage.self, forKey: .saverLanguage) ?? .english
        showClock = try values.decodeIfPresent(Bool.self, forKey: .showClock) ?? true
        showDate = try values.decodeIfPresent(Bool.self, forKey: .showDate) ?? true
        timeFormat = try values.decodeIfPresent(AmbientTimeFormat.self, forKey: .timeFormat) ?? .automatic
        showAMPM = try values.decodeIfPresent(Bool.self, forKey: .showAMPM) ?? true
        pageDuration = try values.decodeIfPresent(Int.self, forKey: .pageDuration) ?? 20
        burnInProtection = try values.decodeIfPresent(Bool.self, forKey: .burnInProtection) ?? true
    }
    public static func read() -> Self {
        guard let url = try? SnapshotLocations.saverPreferences(),
              let data = try? Data(contentsOf: url), data.count < 65_536,
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    public func write() throws {
        let url = try SnapshotLocations.saverPreferences()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
public enum AmbientTimeText {
    public static func time(_ date: Date, format: AmbientTimeFormat, showAMPM: Bool = true, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = .current
        switch format {
        case .automatic:
            formatter.setLocalizedDateFormatFromTemplate("jm")
        case .twentyFourHour: formatter.dateFormat = "HH:mm"
        case .twelveHour:
            formatter.dateFormat = showAMPM ? "h:mm a" : "h:mm"
            formatter.amSymbol = "AM"; formatter.pmSymbol = "PM"
        }
        return formatter.string(from: date)
    }
}
