import Testing

@testable import MeterCore

private func sample(_ at: Double, cpu: Int? = 100, gpu: Int? = 0, ram: Int? = 930)
  -> HistorySample
{
  HistorySample(at: at, cpu: cpu, gpu: gpu, ram: ram)
}

@Suite("The five-minute history (D53, D113)")
struct HistoryWindowTests {
  @Test("a sample exactly five minutes old is kept; a millisecond older is dropped")
  func edge() {
    var history = History()
    history.record(sample(0))
    history.record(sample(300))
    #expect(history.samples.map(\.at) == [0, 300])
    history.trim(now: 300.001)
    #expect(history.samples.map(\.at) == [300])
  }

  @Test("recording drops what has fallen out of the window: nothing older is kept")
  func recordTrims() {
    var history = History()
    for second in stride(from: 0.0, through: 400, by: 0.5) {
      history.record(sample(second))
    }
    #expect(history.samples.first?.at == 100)
    #expect(history.samples.last?.at == 400)
    #expect(history.samples.count == 601)
  }

  @Test("a sample not later than the newest one held is not recorded")
  func inOrder() {
    var history = History()
    history.record(sample(10))
    history.record(sample(10))
    history.record(sample(9))
    #expect(history.samples.map(\.at) == [10])
  }
}

@Suite("Sleep is a gap in the history (D52)")
struct HistorySleepTests {
  @Test("the lines stop at sleep and resume at wake, never joined across it")
  func gap() {
    var history = History()
    for at in [0.0, 0.5, 1.0] { history.record(sample(at)) }
    history.sleep(at: 1.2)
    history.wake(at: 121.2)
    for at in [121.5, 122.0] { history.record(sample(at)) }
    let lines = history.lines(.cpu, now: 122)
    #expect(lines.count == 2)
    #expect(lines[0].count == 3)
    #expect(lines[1].count == 2)
    #expect(lines[0].last?.x == History.position(age: 121, tenths: 1000).x)
    #expect(lines[1].first?.x == History.position(age: 0.5, tenths: 1000).x)
  }

  @Test("nothing is recorded while the Mac is asleep")
  func asleep() {
    var history = History()
    history.record(sample(0))
    history.sleep(at: 1)
    history.record(sample(2))
    history.record(sample(60))
    #expect(history.samples.map(\.at) == [0])
    history.wake(at: 120)
    history.record(sample(120.5))
    #expect(history.samples.map(\.at) == [0, 120.5])
  }

  @Test("a wake keeps the history from before the sleep")
  func notCleared() {
    var history = History()
    for at in stride(from: 0.0, through: 60, by: 0.5) { history.record(sample(at)) }
    history.sleep(at: 60)
    history.wake(at: 180)
    #expect(history.samples.count == 121)
  }

  @Test("a clock jumped forward on wake leaves only what is under five minutes old")
  func jumpForward() {
    var history = History()
    for at in stride(from: 0.0, through: 100, by: 0.5) { history.record(sample(at)) }
    history.sleep(at: 100)
    history.wake(at: 350)
    #expect(history.samples.first?.at == 50)
    history.sleep(at: 350)
    history.wake(at: 1000)
    #expect(history.samples.isEmpty)
    #expect(history.lines(.ram, now: 1000).isEmpty)
  }

  @Test("a clock jumped back on wake drops only the samples it cannot place, and lines go on")
  func jumpBack() {
    var history = History()
    for at in stride(from: 0.0, through: 100, by: 0.5) { history.record(sample(at)) }
    history.sleep(at: 100)
    history.wake(at: 80)
    #expect(history.samples.last?.at == 80)
    #expect(history.samples.count == 161)
    history.record(sample(80.5))
    let lines = history.lines(.gpu, now: 80.5)
    #expect(lines.count == 2)
    #expect(lines.allSatisfy { run in run.allSatisfy { $0.x >= 0 && $0.x <= 1 } })
  }

  @Test("a reading with no fresh value breaks only its own line")
  func dashBreaksLine() {
    var history = History()
    history.record(sample(0, gpu: 10))
    history.record(sample(0.5, gpu: nil))
    history.record(sample(1, gpu: 20))
    #expect(history.lines(.gpu, now: 1).count == 2)
    #expect(history.lines(.cpu, now: 1).count == 1)
  }
}

@Suite("The graph's axes are fixed (D50, D51)")
struct GraphAxisTests {
  @Test(
    "y runs from 0% to 100% whatever the data",
    arguments: [(0, 0.0), (55, 0.055), (100, 0.1), (500, 0.5), (930, 0.93), (1000, 1.0)])
  func scale(tenths: Int, y: Double) {
    var history = History()
    history.record(sample(0, cpu: tenths))
    history.record(sample(1, cpu: tenths))
    let point = history.lines(.cpu, now: 1)[0][1]
    #expect(abs(point.y - y) < 1e-12)
  }

  @Test("a value outside 0% to 100% stays on the scale's ends")
  func clamped() {
    #expect(History.position(age: 0, tenths: 1200).y == 1)
    #expect(History.position(age: 0, tenths: -5).y == 0)
  }

  @Test("x runs from five minutes ago to now, however short the history")
  func timeAxis() {
    var history = History()
    for at in stride(from: 0.0, through: 30, by: 0.5) { history.record(sample(at)) }
    let line = history.lines(.ram, now: 30)[0]
    #expect(abs(line[0].x - 0.9) < 1e-12)
    #expect(line.last?.x == 1)
    #expect(History.position(age: 300, tenths: 0).x == 0)
    #expect(History.position(age: 150, tenths: 0).x == 0.5)
  }
}
