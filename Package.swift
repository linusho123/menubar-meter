// swift-tools-version:6.0
import PackageDescription

// The meter builds with Swift Package Manager from the Command Line Tools;
// no Xcode project. `scripts/build-app.sh` bundles and ad-hoc signs it.
//
// METER_TEST_SOURCE: the test-only reading source (Givens feed it) is
// compiled in only when the build passes `-Xswiftc -DMETER_TEST_SOURCE`.
// The installed app is built without it.
let package = Package(
    name: "menubar-meter",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "MeterCore",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "Meter",
            dependencies: ["MeterCore"],
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        // Test harness helper, never bundled into the app: reads the menu bar
        // through the Accessibility API and shows a stand-in status item.
        .executableTarget(
            name: "meter-harness",
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ApplicationServices")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
