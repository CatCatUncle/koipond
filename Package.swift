// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KoiPond",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "KoiPond", targets: ["KoiPond"])],
    targets: [.executableTarget(name: "KoiPond", resources: [.process("Resources")])],
    // SpriteKit isn't annotated for strict concurrency yet.
    swiftLanguageModes: [.v5]
)
