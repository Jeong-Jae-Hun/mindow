import CoreGraphics
import Testing
@testable import MindowCore

@Suite("같은 키 반복 순환")
struct RepeatCycleTests {
    let half = CGRect(x: 0, y: 0, width: 600, height: 900)

    @Test("같은 동작을 창이 그대로일 때 다시 누르면 다음 단계로 간다")
    func 순환() {
        var cycle = RepeatCycle()
        #expect(cycle.begin(.moveToLeftHalf, current: .zero) == 0)
        cycle.finish(applied: half)
        #expect(cycle.begin(.moveToLeftHalf, current: half) == 1)
        cycle.finish(applied: half)
        #expect(cycle.begin(.moveToLeftHalf, current: half) == 2)
        cycle.finish(applied: half)
        #expect(cycle.begin(.moveToLeftHalf, current: half) == 0)
    }

    @Test("그 사이 창을 옮겼거나 다른 동작이면 처음부터 시작한다")
    func 초기화() {
        var cycle = RepeatCycle()
        _ = cycle.begin(.moveToLeftHalf, current: .zero)
        cycle.finish(applied: half)
        #expect(cycle.begin(.moveToLeftHalf, current: half.offsetBy(dx: 50, dy: 0)) == 0)
        cycle.finish(applied: half)
        #expect(cycle.begin(.moveToRightHalf, current: half) == 0)
    }

    @Test("순환하지 않는 동작은 항상 0단계다")
    func 비순환() {
        var cycle = RepeatCycle()
        _ = cycle.begin(.moveToFullscreen, current: .zero)
        cycle.finish(applied: half)
        #expect(cycle.begin(.moveToFullscreen, current: half) == 0)
    }
}
