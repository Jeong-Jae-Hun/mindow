import CoreGraphics
import Testing
@testable import MindowCore

@Suite("1/4·2/3·세로 1/3·최대 높이 배치 계산")
struct ExtraLayoutTests {
    let landscape = CGRect(x: 0, y: 25, width: 1200, height: 900)
    let portrait = CGRect(x: 0, y: 0, width: 900, height: 1600)
    let window = CGRect(x: 100, y: 125, width: 400, height: 300)

    func place(_ action: WindowAction, _ context: (screen: CGRect, window: CGRect?, previous: Int?)) -> WindowLayout.Placement? {
        WindowLayout.placement(for: action, in: .init(window: context.window ?? window, screen: context.screen, previousStep: context.previous))
    }

    @Test("가로 화면의 1/4은 4열로 나누고 다음은 현재 칸 다음, 이전은 마지막 칸부터 간다")
    func 가로사분할() {
        #expect(place(.moveToNextFourth, (landscape, nil, nil)) == .init(frame: CGRect(x: 0, y: 25, width: 300, height: 900), step: 0))
        #expect(place(.moveToPreviousFourth, (landscape, nil, nil)) == .init(frame: CGRect(x: 900, y: 25, width: 300, height: 900), step: 3))
        let second = CGRect(x: 300, y: 25, width: 300, height: 900)
        #expect(place(.moveToNextFourth, (landscape, second, nil))?.frame == CGRect(x: 600, y: 25, width: 300, height: 900))
        #expect(place(.moveToPreviousFourth, (landscape, second, nil))?.frame == CGRect(x: 0, y: 25, width: 300, height: 900))
    }

    @Test("1/4은 기억한 칸 번호로 넷째 칸 다음에 첫 칸으로 돌아온다")
    func 사분할순환() {
        #expect(place(.moveToNextFourth, (landscape, nil, 2))?.step == 3)
        #expect(place(.moveToNextFourth, (landscape, nil, 3))?.step == 0)
        #expect(place(.moveToPreviousFourth, (landscape, nil, 0))?.step == 3)
    }

    @Test("세로 화면의 1/4은 4행으로 나눈다")
    func 세로화면사분할() {
        #expect(place(.moveToNextFourth, (portrait, nil, nil))?.frame == CGRect(x: 0, y: 0, width: 900, height: 400))
        let second = CGRect(x: 0, y: 400, width: 900, height: 400)
        #expect(place(.moveToNextFourth, (portrait, second, nil))?.frame == CGRect(x: 0, y: 800, width: 900, height: 400))
    }

    @Test("세로 1/3은 가로 화면에서도 3행으로 나눈다")
    func 세로삼분할() {
        #expect(place(.moveToNextRowThird, (landscape, nil, nil)) == .init(frame: CGRect(x: 0, y: 25, width: 1200, height: 300), step: 0))
        #expect(place(.moveToPreviousRowThird, (landscape, nil, nil)) == .init(frame: CGRect(x: 0, y: 625, width: 1200, height: 300), step: 2))
        let top = CGRect(x: 0, y: 25, width: 1200, height: 300)
        #expect(place(.moveToNextRowThird, (landscape, top, nil))?.frame == CGRect(x: 0, y: 325, width: 1200, height: 300))
        #expect(place(.moveToNextRowThird, (portrait, nil, nil))?.frame == CGRect(x: 0, y: 0, width: 900, height: 533))
    }

    @Test("세로 1/3은 너비 전체인 창만 걸친 칸으로 보고, 아니면 첫 칸부터 간다")
    func 세로삼분할칸판정() {
        // Full height but not full width: a column third, not a row cell.
        let column = CGRect(x: 0, y: 25, width: 400, height: 900)
        #expect(place(.moveToNextRowThird, (landscape, column, nil))?.step == 0)
        let tallMiddle = CGRect(x: 0, y: 300, width: 1200, height: 400)
        #expect(place(.moveToNextRowThird, (landscape, tallMiddle, nil))?.step == 2)
    }

    @Test("가운데 2/3은 너비 2/3, 높이 전체로 가운데에 둔다")
    func 가운데이분의삼() {
        #expect(place(.moveToCenterTwoThirds, (landscape, nil, nil)) == .init(frame: CGRect(x: 200, y: 25, width: 800, height: 900), step: 0))
        #expect(place(.moveToCenterTwoThirds, (portrait, nil, nil))?.frame == CGRect(x: 150, y: 0, width: 600, height: 1600))
    }

    @Test("앞·뒤 2/3은 가로 화면에서 왼·오른쪽, 세로 화면에서 위·아래다")
    func 앞뒤이분의삼() {
        #expect(place(.moveToFirstTwoThirds, (landscape, nil, nil)) == .init(frame: CGRect(x: 0, y: 25, width: 800, height: 900), step: 0))
        #expect(place(.moveToLastTwoThirds, (landscape, nil, nil))?.frame == CGRect(x: 400, y: 25, width: 800, height: 900))
        #expect(place(.moveToFirstTwoThirds, (portrait, nil, nil))?.frame == CGRect(x: 0, y: 0, width: 900, height: 1067))
        #expect(place(.moveToLastTwoThirds, (portrait, nil, nil))?.frame == CGRect(x: 0, y: 533, width: 900, height: 1067))
    }

    @Test("반복 순환하지 않는 배치는 기억한 단계가 있어도 같은 자리, 단계 0이다")
    func 비순환배치() {
        #expect(place(.moveToFirstTwoThirds, (landscape, nil, 0)) == place(.moveToFirstTwoThirds, (landscape, nil, nil)))
        #expect(place(.moveToCenterTwoThirds, (landscape, nil, 1))?.step == 0)
    }

    @Test("최대 높이는 x와 너비를 유지하고 높이만 화면 전체로 늘린다")
    func 최대높이() {
        #expect(place(.maximizeHeight, (landscape, nil, nil)) == .init(frame: CGRect(x: 100, y: 25, width: 400, height: 900), step: 0))
        #expect(place(.maximizeHeight, (portrait, nil, nil))?.frame == CGRect(x: 100, y: 0, width: 400, height: 1600))
    }
}
