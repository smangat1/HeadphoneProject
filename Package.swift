// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "HeadphoneProject",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "earpods-launcher", targets: ["earpods-launcher"]),
        .executable(name: "earpods-probe", targets: ["earpods-probe"]),
    ],
    targets: [
        .target(
            name: "EarPodsCore"
        ),
        .executableTarget(
            name: "earpods-probe",
            dependencies: ["EarPodsCore"]
        ),
        .executableTarget(
            name: "earpods-launcher",
            dependencies: ["EarPodsCore"]
        ),
    ]
)
