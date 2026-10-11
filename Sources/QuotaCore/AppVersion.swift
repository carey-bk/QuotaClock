import Foundation

/// Release precedence deliberately ignores prerelease/build suffixes: the same
/// public release never prompts again solely because its internal build changed.
public struct AppVersion: Comparable, Equatable, Sendable {
    public let components: [Int]
    public init?(_ raw: String) {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") { value.removeFirst() }
        let core = value.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? ""
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              parts.allSatisfy({ Int($0) != nil }) else { return nil }
        components = parts.map { Int($0)! } + (parts.count == 2 ? [0] : [])
    }
    public var display: String { "v" + components.map(String.init).joined(separator: ".") }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
    public static func display(in bundle: Bundle = .main) -> String {
        (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(Self.init)?.display ?? "—"
    }
}
