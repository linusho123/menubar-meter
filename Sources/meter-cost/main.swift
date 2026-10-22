import Foundation
import OwnCost

// Test harness helper: the arithmetic of the meter's own cost (OwnCost) over readings that
// macOS's own tools took of the meter from outside. It never talks to the meter itself.
//
//   meter-cost cpu <cores>        stdin: one "<epoch ms>\t<ps -o time= text>" line per sample;
//                                 prints {mean, peak, seconds} as shares of the whole Mac in %
//   meter-cost footprint          stdin: `footprint -f bytes --noCategories -p <pid>` output;
//                                 prints {bytes, shown, under50}, as Activity Monitor's Memory

struct CPUResult: Encodable {
  var mean: Double
  var peak: Double
  var seconds: Double
}

struct MemoryResult: Encodable {
  var bytes: UInt64
  var shown: String
  var under50: Bool
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

func emit<T: Encodable>(_ value: T) {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  guard let data = try? encoder.encode(value) else { fail("meter-cost: cannot encode") }
  print(String(decoding: data, as: UTF8.self))
}

let input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
let arguments = CommandLine.arguments
switch arguments.count > 1 ? arguments[1] : "" {
case "cpu":
  guard arguments.count == 3, let cores = Int(arguments[2]) else { fail("usage: cpu <cores>") }
  var samples: [CPUTimeSample] = []
  for line in input.split(separator: "\n") {
    let fields = line.split(separator: "\t")
    guard fields.count == 2, let at = Double(fields[0]),
      let seconds = PSTime.seconds(String(fields[1]))
    else { fail("cpu: not a sample: \(line)") }
    samples.append(CPUTimeSample(at: at, cpuSeconds: seconds))
  }
  guard let share = CPUShare.over(samples, cores: cores) else {
    fail("cpu: no share over \(samples.count) samples")
  }
  emit(CPUResult(mean: share.mean, peak: share.peak, seconds: share.seconds))
case "footprint":
  guard let bytes = ActivityMonitorMemory.physicalFootprint(footprintOutput: input) else {
    fail("footprint: no phys_footprint in: \(input)")
  }
  emit(
    MemoryResult(
      bytes: bytes, shown: ActivityMonitorMemory.text(bytes: bytes),
      under50: ActivityMonitorMemory.isUnder(bytes: bytes, megabytes: 50)))
default:
  fail("usage: meter-cost cpu <cores> | footprint")
}
