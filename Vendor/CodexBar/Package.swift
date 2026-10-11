// swift-tools-version: 6.2
import PackageDescription
// QuotaClock packages only the upstream data layer and CLI, not the upstream app.
let package = Package(name: "CodexBar", platforms: [.macOS(.v14)], products: [
    .executable(name: "CodexBarCLI", targets: ["CodexBarCLI"])
], dependencies: [
    .package(url: "https://github.com/steipete/Commander", from: "0.2.4"),
    .package(url: "https://github.com/apple/swift-crypto.git", from: "4.5.2"),
    .package(url: "https://github.com/apple/swift-log", from: "1.15.1"),
    .package(url: "https://github.com/steipete/SweetCookieKit", from: "0.5.5")
], targets: [
    .target(name: "CQuickJS", path: "Sources/CQuickJS", exclude: ["README.md", "LICENSE"], publicHeadersPath: "include", cSettings: [.define("_GNU_SOURCE")]),
    .target(name: "CodexBarCore", dependencies: ["CQuickJS", .product(name: "Crypto", package: "swift-crypto"), .product(name: "Logging", package: "swift-log"), .product(name: "SweetCookieKit", package: "SweetCookieKit")], resources: [.process("Resources")], swiftSettings: [.enableUpcomingFeature("StrictConcurrency")], linkerSettings: [.linkedFramework("JavaScriptCore")]),
    .executableTarget(name: "CodexBarCLI", dependencies: ["CodexBarCore", .product(name: "Commander", package: "Commander"), .product(name: "Crypto", package: "swift-crypto")], swiftSettings: [.enableUpcomingFeature("StrictConcurrency")])
])
