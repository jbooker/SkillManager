// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SkillManager",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "SkillManagerCore", targets: ["SkillManagerCore"]),
        .executable(name: "SkillManager", targets: ["SkillManager"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.3"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.1"),
    ],
    targets: [
        .target(
            name: "SkillManagerCore",
            dependencies: ["Yams"]
        ),
        .executableTarget(
            name: "SkillManager",
            dependencies: [
                "SkillManagerCore",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ]
        ),
        .testTarget(
            name: "SkillManagerCoreTests",
            dependencies: ["SkillManagerCore"]
        ),
    ]
)
