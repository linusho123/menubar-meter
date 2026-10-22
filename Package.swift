// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "Meter",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Meter", targets: ["Meter"]),
    .executable(name: "meter-ax", targets: ["meter-ax"]),
    .executable(name: "meter-neighbor", targets: ["meter-neighbor"]),
    .executable(name: "meter-gpu-load", targets: ["meter-gpu-load"]),
    .executable(name: "meter-standin", targets: ["meter-standin"]),
    .executable(name: "meter-cost", targets: ["meter-cost"]),
  ],
  targets: [
    // Sampling arithmetic, formatting and staleness. No AppKit, no system calls.
    .target(name: "MeterCore"),
    // The meter's clock, apart so a test can pin it to the system's (counts sleep).
    .target(name: "MeterClock"),
    // The menu bar app: real system inputs, the status item, and (test builds only,
    // compiled in by -DMETER_TEST_SOURCE) the test reading source.
    .executableTarget(name: "Meter", dependencies: ["MeterCore", "MeterClock"]),
    // Test harness helpers, never bundled into the app.
    .executableTarget(name: "meter-ax"),
    .executableTarget(name: "meter-neighbor"),
    .executableTarget(name: "meter-gpu-load"),
    .executableTarget(name: "meter-standin"),
    // The harness's arithmetic for the meter's own cost, measured from outside it (P7).
    .target(name: "OwnCost"),
    .executableTarget(name: "meter-cost", dependencies: ["OwnCost"]),
    .testTarget(name: "MeterCoreTests", dependencies: ["MeterCore"]),
    .testTarget(name: "MeterClockTests", dependencies: ["MeterClock"]),
    .testTarget(name: "OwnCostTests", dependencies: ["OwnCost"]),
  ]
)
