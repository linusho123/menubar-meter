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
  ],
  targets: [
    // Sampling arithmetic, formatting and staleness. No AppKit, no system calls.
    .target(name: "MeterCore"),
    // The menu bar app: real system inputs, the status item, and (test builds only,
    // compiled in by -DMETER_TEST_SOURCE) the test reading source.
    .executableTarget(name: "Meter", dependencies: ["MeterCore"]),
    // Test harness helpers, never bundled into the app.
    .executableTarget(name: "meter-ax"),
    .executableTarget(name: "meter-neighbor"),
    .executableTarget(name: "meter-gpu-load"),
    .executableTarget(name: "meter-standin"),
    .testTarget(name: "MeterCoreTests", dependencies: ["MeterCore"]),
  ]
)
