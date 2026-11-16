import CoreGraphics
import Testing
@testable import MindowCore

@Suite("같은 키 반복 순환")
struct RepeatCycleTests {
    let half = CGRect(x: 0, y: 0, width: 600, height: 900)

    @Test("같은 동작을 창이 그대로일 때 다시 누르면 지난 단계를 돌려준다")
    func 이어가기() {
        var cycle = RepeatCycle()
        #expect(cycle.previousStep(for: .moveToLeftHalf, current: half) == nil)
        cycle.record(.moveToLeftHalf, placement: .init(frame: half, step: 1))
        #expect(cycle.previousStep(for: .moveToLeftHalf, current: half) == 1)
    }

    @Test("그 사이 창을 옮겼거나 다른 동작이면 처음부터 시작한다")
    func 초기화() {
        var cycle = RepeatCycle()
        cycle.record(.moveToLeftHalf, placement: .init(frame: half, step: 0))
        #expect(cycle.previousStep(for: .moveToLeftHalf, current: half.offsetBy(dx: 50, dy: 0)) == nil)
        #expect(cycle.previousStep(for: .moveToRightHalf, current: half) == nil)
    }

    @Test("다음·이전 1/3은 서로의 칸 번호를 이어받는다")
    func 삼분할이어가기() {
        var cycle = RepeatCycle()
        cycle.record(.moveToNextThird, placement: .init(frame: half, step: 2))
        #expect(cycle.previousStep(for: .moveToPreviousThird, current: half) == 2)
    }

    @Test("다음·이전 1/4, 다음·이전 세로 1/3도 같은 묶음끼리 칸 번호를 이어받는다")
    func 같은칸묶음이어가기() {
        var cycle = RepeatCycle()
        cycle.record(.moveToNextFourth, placement: .init(frame: half, step: 3))
        #expect(cycle.previousStep(for: .moveToPreviousFourth, current: half) == 3)
        #expect(cycle.previousStep(for: .moveToNextFourth, current: half) == 3)
        cycle.record(.moveToPreviousRowThird, placement: .init(frame: half, step: 1))
        #expect(cycle.previousStep(for: .moveToNextRowThird, current: half) == 1)
    }

    @Test("칸 묶음이 다르면 칸 번호를 이어받지 않는다")
    func 다른칸묶음() {
        var cycle = RepeatCycle()
        cycle.record(.moveToNextFourth, placement: .init(frame: half, step: 3))
        #expect(cycle.previousStep(for: .moveToNextThird, current: half) == nil)
        #expect(cycle.previousStep(for: .moveToNextRowThird, current: half) == nil)
        cycle.record(.moveToNextThird, placement: .init(frame: half, step: 1))
        #expect(cycle.previousStep(for: .moveToPreviousFourth, current: half) == nil)
        #expect(cycle.previousStep(for: .moveToPreviousRowThird, current: half) == nil)
        cycle.record(.moveToNextRowThird, placement: .init(frame: half, step: 1))
        #expect(cycle.previousStep(for: .moveToPreviousThird, current: half) == nil)
    }

    @Test("새 배치 동작은 반복 순환하지 않는다")
    func 새배치비순환() {
        var cycle = RepeatCycle()
        for action in [WindowAction.moveToCenterTwoThirds, .moveToFirstTwoThirds, .moveToLastTwoThirds, .maximizeHeight] {
            cycle.record(action, placement: .init(frame: half, step: 0))
            #expect(cycle.previousStep(for: action, current: half) == nil)
        }
    }

    @Test("순환하지 않는 동작은 이어받지 않는다")
    func 비순환() {
        var cycle = RepeatCycle()
        cycle.record(.moveToFullscreen, placement: .init(frame: half, step: 0))
        #expect(cycle.previousStep(for: .moveToFullscreen, current: half) == nil)
    }
}
