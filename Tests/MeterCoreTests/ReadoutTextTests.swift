import Foundation
import Testing

@testable import MeterCore

@Suite("The menu bar text (D89, D90, D114)")
struct ReadoutTextTests {
  @Test("the label order is CPU, GPU, RAM, then the temperature")
  func labelOrder() {
    let text = ReadoutText.text(Readout(cpu: 1, gpu: 2, ram: 3, temperature: 4))
    let cpu = text.range(of: "CPU")!.lowerBound
    let gpu = text.range(of: "GPU")!.lowerBound
    let ram = text.range(of: "RAM")!.lowerBound
    let degrees = text.range(of: "°C")!.lowerBound
    #expect(cpu < gpu && gpu < ram && ram < degrees)
    #expect(text == "CPU   1%  GPU   2%  RAM   3%    4°C")
  }

  @Test("the contract's three readings, exactly")
  func contractRows() {
    #expect(
      ReadoutText.text(Readout(cpu: 100, gpu: 7, ram: 93, temperature: 98))
        == "CPU 100%  GPU   7%  RAM  93%   98°C")
    #expect(
      ReadoutText.text(Readout(cpu: 7, gpu: 100, ram: 9, temperature: 61))
        == "CPU   7%  GPU 100%  RAM   9%   61°C")
    #expect(
      ReadoutText.text(Readout(cpu: 0, gpu: 0, ram: 0, temperature: 35))
        == "CPU   0%  GPU   0%  RAM   0%   35°C")
  }

  @Test("every slot is three characters wide, numbers right-aligned", arguments: [0, 7, 42, 100])
  func slotWidth(value: Int) {
    let slot = ReadoutText.slot(value)
    #expect(slot.count == 3)
    #expect(slot.hasSuffix(String(value)))
    let text = ReadoutText.text(Readout(cpu: value, gpu: value, ram: value, temperature: value))
    #expect(text.count == ReadoutText.widest.count)
  }

  @Test("a dash fills the same slot, so the width holds")
  func dashKeepsWidth() {
    #expect(ReadoutText.slot(nil) == "  \u{2013}")
    let dashed = ReadoutText.text(Readout(cpu: nil, gpu: nil, ram: nil, temperature: nil))
    #expect(dashed == "CPU   –%  GPU   –%  RAM   –%    –°C")
    #expect(dashed.count == ReadoutText.widest.count)
  }

  @Test("only the stale value turns into a dash")
  func oneDash() {
    let text = ReadoutText.text(Readout(cpu: 30, gpu: nil, ram: 40, temperature: 50))
    #expect(text == "CPU  30%  GPU   –%  RAM  40%   50°C")
  }

  @Test("a number too wide for its slot is a dash, never a clipped number")
  func overflow() {
    #expect(ReadoutText.slot(1000) == "  \u{2013}")
    #expect(ReadoutText.slot(-1) == "  \u{2013}")
  }
}
