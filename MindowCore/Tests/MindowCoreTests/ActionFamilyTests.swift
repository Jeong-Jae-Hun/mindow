import Testing
@testable import MindowCore

@Suite("동작 묶음")
struct ActionFamilyTests {
    @Test("묶음을 모두 펼치면 모든 동작이 한 번씩 나온다")
    func 빠짐없이() {
        let listed = WindowAction.Family.allCases.flatMap(\.actions)
        #expect(listed.count == WindowAction.allCases.count)
        #expect(Set(listed) == Set(WindowAction.allCases))
    }

    @Test("빈 묶음이 없고 제목이 겹치지 않는다")
    func 묶음제목() {
        let families = WindowAction.Family.allCases
        #expect(families.allSatisfy { !$0.actions.isEmpty })
        #expect(Set(families.map(\.title)).count == families.count)
    }

    @Test("1/3·1/4·세로 1/3은 한 묶음이고 가운데 2/3는 2/3 묶음에 든다")
    func 소속() {
        #expect(WindowAction.Family.cells.actions == [
            .moveToNextThird, .moveToPreviousThird, .moveToNextFourth, .moveToPreviousFourth,
            .moveToNextRowThird, .moveToPreviousRowThird,
        ])
        #expect(WindowAction.moveToCenterTwoThirds.family == .twoThirds)
        #expect(WindowAction.maximizeHeight.family == .fill)
    }
}
