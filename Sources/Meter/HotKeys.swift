import Carbon
import MeterCore

/// The shortcut that opens and closes the panel from any app, and Esc while the panel is open
/// (D98). System-wide hot keys through Carbon's `RegisterEventHotKey`, which needs no
/// Accessibility or Input Monitoring permission and sees only its own combinations.
@MainActor
final class HotKeys {
  private static let signature: OSType = 0x4D_54_52_4D  // 'MTRM'
  private static var actions: [UInt32: () -> Void] = [:]
  private static var installed = false

  private var refs: [UInt32: EventHotKeyRef] = [:]

  /// Registers `key` as hot key number `id`; `action` runs on the main thread when it is pressed.
  /// Returns false when macOS refused the combination (another app holds it).
  @discardableResult
  func register(_ key: HotKey, id: UInt32, action: @escaping () -> Void) -> Bool {
    Self.installHandler()
    unregister(id: id)
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      key.keyCode, key.modifiers, EventHotKeyID(signature: Self.signature, id: id),
      GetApplicationEventTarget(), 0, &ref)
    guard status == noErr, let ref else {
      FileHandle.standardError.write(Data("meter: hot key \(id) not registered (\(status))\n".utf8))
      return false
    }
    refs[id] = ref
    Self.actions[id] = action
    return true
  }

  func unregister(id: UInt32) {
    if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
    Self.actions[id] = nil
  }

  private static func installHandler() {
    guard !installed else { return }
    installed = true
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, _ -> OSStatus in
        var hotKey = EventHotKeyID()
        let status = GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
          MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
        guard status == noErr, hotKey.signature == HotKeys.signature else {
          return OSStatus(eventNotHandledErr)
        }
        let id = hotKey.id
        MainActor.assumeIsolated { HotKeys.actions[id]?() }
        return noErr
      }, 1, &spec, nil, nil)
  }
}
