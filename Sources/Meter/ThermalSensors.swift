import Foundation
import IOKit

// The die temperature sensors macOS publishes as HID event services. Reading them needs no
// admin password (D87). These functions live in IOKit but have no public header.
private typealias HIDClient = OpaquePointer
private typealias HIDService = OpaquePointer
private typealias HIDEvent = OpaquePointer

@_silgen_name("IOHIDEventSystemClientCreate")
private func hidClientCreate(_ allocator: CFAllocator?) -> HIDClient?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func hidClientSetMatching(_ client: HIDClient, _ match: CFDictionary) -> Int32

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func hidClientCopyServices(_ client: HIDClient) -> Unmanaged<CFArray>?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func hidServiceCopyProperty(_ service: HIDService, _ key: CFString) -> Unmanaged<
  CFTypeRef
>?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func hidServiceCopyEvent(
  _ service: HIDService, _ type: Int64, _ options: Int32, _ timestamp: Int64
) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventGetFloatValue")
private func hidEventGetFloatValue(_ event: HIDEvent, _ field: Int32) -> Double

final class ThermalSensors {
  private static let temperatureEvent: Int64 = 15
  private static let temperatureField = Int32(15 << 16)

  private var services: [(name: String, service: AnyObject)] = []

  init() {
    guard let client = hidClientCreate(kCFAllocatorDefault) else { return }
    // Vendor usage page 0xff00, usage 5: the temperature sensors.
    let match: [String: Int] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5]
    _ = hidClientSetMatching(client, match as CFDictionary)
    guard let list = hidClientCopyServices(client)?.takeRetainedValue() as? [AnyObject] else {
      return
    }
    for service in list {
      let pointer = OpaquePointer(Unmanaged.passUnretained(service).toOpaque())
      let name = hidServiceCopyProperty(pointer, "Product" as CFString)?.takeRetainedValue()
      if let name = name as? String {
        services.append((name, service))
      }
    }
  }

  func read() -> [String: Double]? {
    var sensors: [String: Double] = [:]
    for (name, service) in services {
      let pointer = OpaquePointer(Unmanaged.passUnretained(service).toOpaque())
      guard
        let event = hidServiceCopyEvent(pointer, Self.temperatureEvent, 0, 0)?
          .takeRetainedValue()
      else { continue }
      let eventPointer = OpaquePointer(Unmanaged.passUnretained(event).toOpaque())
      sensors[name] = hidEventGetFloatValue(eventPointer, Self.temperatureField)
    }
    return sensors.isEmpty ? nil : sensors
  }
}
