import CoreGraphics
import Testing
@testable import MindowCore

@Suite("창 간격 배치 계산")
struct GapLayoutTests {
    let landscape = CGRect(x: 0, y: 25, width: 1200, height: 900)
    let portrait = CGRect(x: 0, y: 0, width: 900, height: 1600)
    let window = CGRect(x: 100, y: 125, width: 400, height: 300)

    func place(_ action: WindowAction, _ context: (screen: CGRect, window: CGRect?, previous: Int?, gap: CGFloat)) -> WindowLayout.Placement? {
        WindowLayout.placement(
            for: action,
            in: .init(window: context.window ?? window, screen: context.screen, previousStep: context.previous, gap: context.gap)
        )
    }

    @Test("절반은 화면 가장자리에서 간격만큼, 맞닿은 절반끼리도 간격만큼 떨어진다")
    func 절반() {
        #expect(place(.moveToLeftHalf, (landscape, nil, nil, 8))?.frame == CGRect(x: 8, y: 33, width: 588, height: 884))
        #expect(place(.moveToRightHalf, (landscape, nil, nil, 8))?.frame == CGRect(x: 604, y: 33, width: 588, height: 884))
        #expect(place(.moveToTopHalf, (landscape, nil, nil, 8))?.frame == CGRect(x: 8, y: 33, width: 1184, height: 438))
        #expect(place(.moveToBottomHalf, (landscape, nil, nil, 8))?.frame == CGRect(x: 8, y: 479, width: 1184, height: 438))
    }

    @Test("코너는 위아래·좌우 이웃과 간격만큼 떨어진다")
    func 코너() {
        #expect(place(.moveToUpperLeft, (landscape, nil, nil, 8))?.frame == CGRect(x: 8, y: 33, width: 588, height: 438))
        #expect(place(.moveToLowerRight, (landscape, nil, nil, 8))?.frame == CGRect(x: 604, y: 479, width: 588, height: 438))
    }

    @Test("1/3·1/4·세로 1/3 칸은 바깥 칸과 안쪽 칸 모두 이웃과 간격만큼 떨어진다")
    func 칸() {
        #expect(place(.moveToNextThird, (landscape, nil, nil, 8)) == .init(frame: CGRect(x: 8, y: 33, width: 388, height: 884), step: 0))
        #expect(place(.moveToNextThird, (landscape, nil, 0, 8))?.frame == CGRect(x: 404, y: 33, width: 392, height: 884))
        #expect(place(.moveToPreviousThird, (landscape, nil, nil, 8))?.frame == CGRect(x: 804, y: 33, width: 388, height: 884))
        #expect(place(.moveToNextFourth, (landscape, nil, 0, 8))?.frame == CGRect(x: 304, y: 33, width: 292, height: 884))
        #expect(place(.moveToNextRowThird, (landscape, nil, nil, 8))?.frame == CGRect(x: 8, y: 33, width: 1184, height: 288))
    }

    @Test("칸 경계가 소수점에 걸려도 이웃 칸 사이는 정확히 간격만큼이다")
    func 소수경계() {
        let odd = CGRect(x: 0, y: 25, width: 1366, height: 743)
        let frames = [nil, 0, 1].compactMap { place(.moveToNextThird, (odd, nil, $0, 8))?.frame }
        #expect(frames.count == 3)
        #expect(frames.first?.minX == 8)
        #expect(frames.last?.maxX == 1358)
        for (a, b) in zip(frames, frames.dropFirst()) {
            #expect(b.minX - a.maxX == 8)
        }
        // A fractional gap is rounded to whole points first, so it never collapses to 0.
        let left = place(.moveToLeftHalf, (landscape, nil, nil, 0.5))?.frame
        let right = place(.moveToRightHalf, (landscape, nil, nil, 0.5))?.frame
        #expect(left.flatMap { l in right.map { $0.minX - l.maxX } } == 1)
    }

    @Test("세로 화면의 1/4·2/3은 행으로 나눠 위아래에 간격을 둔다")
    func 세로화면() {
        #expect(place(.moveToNextFourth, (portrait, nil, nil, 8))?.frame == CGRect(x: 8, y: 8, width: 884, height: 388))
        #expect(place(.moveToNextFourth, (portrait, nil, 0, 8))?.frame == CGRect(x: 8, y: 404, width: 884, height: 392))
        #expect(place(.moveToFirstTwoThirds, (portrait, nil, nil, 8))?.frame == CGRect(x: 8, y: 8, width: 884, height: 1055))
        #expect(place(.moveToLastTwoThirds, (portrait, nil, nil, 8))?.frame == CGRect(x: 8, y: 537, width: 884, height: 1055))
    }

    @Test("2/3·가운데 2/3·전체에도 간격을 두고, 최대 높이는 위아래에만 둔다")
    func 나머지배치() {
        #expect(place(.moveToFirstTwoThirds, (landscape, nil, nil, 8))?.frame == CGRect(x: 8, y: 33, width: 788, height: 884))
        #expect(place(.moveToLastTwoThirds, (landscape, nil, nil, 8))?.frame == CGRect(x: 404, y: 33, width: 788, height: 884))
        #expect(place(.moveToCenterTwoThirds, (landscape, nil, nil, 8))?.frame == CGRect(x: 204, y: 33, width: 792, height: 884))
        #expect(place(.moveToFullscreen, (landscape, nil, nil, 8))?.frame == CGRect(x: 8, y: 33, width: 1184, height: 884))
        #expect(place(.maximizeHeight, (landscape, nil, nil, 8))?.frame == CGRect(x: 100, y: 33, width: 400, height: 884))
        #expect(place(.maximizeHeight, (portrait, nil, nil, 8))?.frame == CGRect(x: 100, y: 8, width: 400, height: 1584))
    }

    @Test("가운데·크기 키우기·줄이기는 간격을 무시한다")
    func 간격제외() {
        for action in [WindowAction.moveToCenter, .makeLarger, .makeSmaller] {
            #expect(place(action, (landscape, nil, nil, 8)) == place(action, (landscape, nil, nil, 0)))
        }
    }

    @Test("간격 0은 간격을 주지 않은 결과와 모든 동작에서 같다")
    func 간격영() {
        for action in WindowAction.allCases {
            for previous in [nil, 0, 1, 2] {
                let plain = WindowLayout.placement(for: action, in: .init(window: window, screen: landscape, previousStep: previous))
                #expect(place(action, (landscape, nil, previous, 0)) == plain)
            }
        }
    }

    @Test("간격이 있어도 같은 키를 다시 누르면 다음 크기·다음 칸으로 이어간다")
    func 반복이어가기() throws {
        var cycle = RepeatCycle()
        let first = try #require(place(.moveToLeftHalf, (landscape, nil, nil, 8)))
        cycle.record(.moveToLeftHalf, placement: first)
        let previous = cycle.previousStep(for: .moveToLeftHalf, current: first.frame)
        #expect(previous == 0)
        #expect(place(.moveToLeftHalf, (landscape, first.frame, previous, 8)) == .init(frame: CGRect(x: 8, y: 33, width: 388, height: 884), step: 1))

        // Without a remembered step, a gapped cell still counts as spanning the cross axis.
        let cell = try #require(place(.moveToNextThird, (landscape, nil, nil, 8))).frame
        #expect(place(.moveToNextThird, (landscape, cell, nil, 8))?.step == 1)
        let row = try #require(place(.moveToNextRowThird, (landscape, nil, nil, 8))).frame
        #expect(place(.moveToNextRowThird, (landscape, row, nil, 8))?.step == 1)
    }
}
