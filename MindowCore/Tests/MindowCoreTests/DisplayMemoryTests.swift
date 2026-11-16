import CoreGraphics
import Testing
@testable import MindowCore

@Suite("모니터 구성별 창 위치 기억")
struct DisplayMemoryTests {
    let laptop = DisplayConfiguration.Display(uuid: "A1", width: 3024, height: 1964)
    let monitor = DisplayConfiguration.Display(uuid: "B2", width: 3840, height: 2160)
    let left = CGRect(x: 0, y: 25, width: 600, height: 900)
    let right = CGRect(x: 1512, y: 0, width: 1920, height: 1080)

    var alone: DisplayConfiguration { DisplayConfiguration([laptop]) }
    var docked: DisplayConfiguration { DisplayConfiguration([laptop, monitor]) }

    @Test("같은 모니터면 나열 순서와 상관없이 같은 구성이고, 해상도가 바뀌면 다른 구성이다")
    func 구성키() {
        #expect(DisplayConfiguration([monitor, laptop]) == docked)
        var scaled = monitor
        scaled.width = 2560
        scaled.height = 1440
        #expect(DisplayConfiguration([laptop, scaled]) != docked)
        #expect(alone != docked)
    }

    @Test("모니터를 뺐다 다시 꽂으면 꽂혀 있을 때 기록한 위치가 돌아온다")
    func 복원() {
        var memory = DisplayMemory<Int, String>(current: docked)
        memory.record(["editor": right], of: 1, in: docked)
        memory.displaysChanged()
        let unplugged = memory.settle(on: alone)
        #expect(unplugged.isEmpty)
        memory.resume()
        memory.record(["editor": left], of: 1, in: alone)
        memory.displaysChanged()
        let replugged = memory.settle(on: docked)
        #expect(replugged == [1: ["editor": right]])
        #expect(memory.current == docked)
    }

    @Test("구성이 바뀐 뒤 복원을 마칠 때까지 기록하지 않고, 마치면 다시 기록한다")
    func 기록멈춤() {
        var memory = DisplayMemory<Int, String>(current: docked)
        memory.record(["editor": right], of: 1, in: docked)
        memory.displaysChanged()
        #expect(memory.isSettling)
        let oldDisplays = memory.record(["editor": left], of: 1, in: docked)
        #expect(!oldDisplays)
        let newDisplays = memory.record(["editor": left], of: 1, in: alone)
        #expect(!newDisplays)
        let restored = memory.settle(on: docked)
        #expect(restored == [1: ["editor": right]])
        let restoring = memory.record(["editor": left], of: 1, in: docked)
        #expect(!restoring)
        memory.resume()
        #expect(!memory.isSettling)
        let resumed = memory.record(["editor": left], of: 1, in: docked)
        #expect(resumed)
    }

    @Test("알림이 오기 전에 읽은 새 구성의 위치는 지금 구성이 아니라서 버린다")
    func 늦은알림() {
        var memory = DisplayMemory<Int, String>(current: docked)
        memory.record(["editor": right], of: 1, in: docked)
        let early = memory.record(["editor": left], of: 1, in: alone)
        #expect(!early)
        memory.displaysChanged()
        memory.record(["editor": left], of: 1, in: alone)
        _ = memory.settle(on: alone)
        memory.displaysChanged()
        let restored = memory.settle(on: docked)
        #expect(restored == [1: ["editor": right]])
    }

    @Test("기록은 앱 단위로 바꾸고, 기록에 없던 앱은 그대로 둔다")
    func 앱단위() {
        var memory = DisplayMemory<Int, String>(current: docked)
        memory.record(["editor": right, "notes": left], of: 1, in: docked)
        memory.record(["chat": left], of: 2, in: docked)
        memory.record(["editor": left], of: 1, in: docked)
        memory.displaysChanged()
        let restored = memory.settle(on: docked)
        #expect(restored == [1: ["editor": left], 2: ["chat": left]])
    }

    @Test("종료한 앱은 모든 구성에서 지운다")
    func 앱종료() {
        var memory = DisplayMemory<Int, String>(current: docked)
        memory.record(["editor": right], of: 1, in: docked)
        memory.record(["chat": right], of: 2, in: docked)
        memory.displaysChanged()
        _ = memory.settle(on: alone)
        memory.resume()
        memory.record(["editor": left], of: 1, in: alone)
        memory.forget(1)
        memory.displaysChanged()
        let dockedRecord = memory.settle(on: docked)
        #expect(dockedRecord == [2: ["chat": right]])
        memory.displaysChanged()
        let aloneRecord = memory.settle(on: alone)
        #expect(aloneRecord == [:])
    }
}
