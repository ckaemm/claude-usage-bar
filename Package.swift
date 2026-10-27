// swift-tools-version:6.0
import Foundation
import PackageDescription

// Yalnızca Command Line Tools kurulu (Xcode yok) ortamlarda Swift Testing framework'ü
// varsayılan arama yolunda değildir; varsa yolu test hedefine ekle.
let cltDev = "/Library/Developer/CommandLineTools/Library/Developer"
let cltFrameworks = cltDev + "/Frameworks"
let testingFlags: (swift: [SwiftSetting], linker: [LinkerSetting]) =
    FileManager.default.fileExists(atPath: cltFrameworks + "/Testing.framework")
    ? ([.unsafeFlags(["-F", cltFrameworks])],
       [.unsafeFlags(["-F", cltFrameworks, "-Xlinker", "-rpath", "-Xlinker", cltFrameworks,
                        "-Xlinker", "-rpath", "-Xlinker", cltDev + "/usr/lib"])])
    : ([], [])

let package = Package(
    name: "ClaudeUsageBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClaudeUsageBar", targets: ["ClaudeUsageBar"]),
    ],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "ClaudeUsageBar", dependencies: ["UsageCore"]),
        .testTarget(
            name: "UsageCoreTests",
            dependencies: ["UsageCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: testingFlags.swift,
            linkerSettings: testingFlags.linker
        ),
    ],
    swiftLanguageModes: [.v5]
)
