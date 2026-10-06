// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "QuotaCore", platforms: [.macOS(.v14)], products: [.library(name: "QuotaCore", targets: ["QuotaCore"])], targets: [.target(name: "QuotaCore"), .testTarget(name: "QuotaCoreTests", dependencies: ["QuotaCore"])])
