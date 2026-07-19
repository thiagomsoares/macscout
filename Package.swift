// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Macscout",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacscoutCore", targets: ["MacscoutCore"]),
        .executable(name: "Macscout", targets: ["Macscout"]),
    ],
    targets: [
        .target(
            name: "MacscoutCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Macscout",
            dependencies: ["MacscoutCore"],
            exclude: ["Resources"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MacscoutCoreTestsRunner",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MacscoutCoreTests",
            dependencies: ["MacscoutCore"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                // CLT-only toolchains ship Testing.framework and its macro
                // plugin outside the default search paths.
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-load-plugin-library", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib",
                    "-enable-experimental-feature", "SymbolLinkageMarkers",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-framework", "Testing",
                    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ]
        ),
    ]
)
