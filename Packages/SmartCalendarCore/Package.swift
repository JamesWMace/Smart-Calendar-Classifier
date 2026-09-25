// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SmartCalendarCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "SmartCalendarCore", targets: ["SmartCalendarCore"]),
    ],
    targets: [
        .target(name: "SmartCalendarCore"),
        .testTarget(
            name: "SmartCalendarCoreTests",
            dependencies: ["SmartCalendarCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
