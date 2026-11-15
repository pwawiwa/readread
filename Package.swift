// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Readread",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Readread",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ReadreadTests",
            dependencies: ["Readread"],
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xfrontend", "-disable-cross-import-overlays"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
                ])
            ]
        )
    ]
)
