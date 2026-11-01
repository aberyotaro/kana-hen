// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "kanahen",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "GobakuCore"),
        .executableTarget(name: "kanahen", dependencies: ["GobakuCore"]),
        // Command Line Tools だけでは XCTest / swift-testing が使えないため、実行形式のテストにしている
        .executableTarget(name: "selftest", dependencies: ["GobakuCore"], path: "Tests/SelfTest"),
    ]
)
