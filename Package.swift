// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "Droplane",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Droplane", targets: ["Droplane"])],
    targets: [
        .systemLibrary(name: "CLibMTP", pkgConfig: "libmtp", providers: [.brew(["libmtp"])]),
        .target(name: "TransferCore"),
        .target(name: "MTPBridge", dependencies: ["CLibMTP", "TransferCore"]),
        .executableTarget(name: "Droplane", dependencies: ["TransferCore", "MTPBridge"]),
        .testTarget(name: "TransferCoreTests", dependencies: ["TransferCore"]),
    ]
)
