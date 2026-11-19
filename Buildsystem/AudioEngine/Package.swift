// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VLCKit",
    products: [.library(name: "VLCKit", targets: ["VLCKit"])],
    targets: [.binaryTarget(name: "VLCKit", path: "Artifacts/VLCKit.xcframework")]
)
