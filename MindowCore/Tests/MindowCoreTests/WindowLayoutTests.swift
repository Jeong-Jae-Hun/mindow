import CoreGraphics
import Testing
@testable import MindowCore

@Suite("창 배치 계산")
struct WindowLayoutTests {
    let screen = CGRect(x: 0, y: 25, width: 1200, height: 900)
    let window = CGRect(x: 100, y: 125, width: 400, height: 300)

    func place(_ action: WindowAction, _ context: (previous: Int?, window: CGRect?)) -> WindowLayout.Placement? {
        WindowLayout.placement(for: action, in: .init(window: context.window ?? window, screen: screen, previousStep: context.previous))
    }

    func frame(_ action: WindowAction, _ context: (previous: Int?, window: CGRect?)) -> CGRect? {
        place(action, context)?.frame
    }

    @Test("절반은 반복할 때마다 1/2, 1/3, 2/3 너비로 돌고 다시 1/2로 온다")
    func 절반순환() {
        #expect(place(.moveToLeftHalf, (nil, nil)) == .init(frame: CGRect(x: 0, y: 25, width: 600, height: 900), step: 0))
        #expect(place(.moveToLeftHalf, (0, nil)) == .init(frame: CGRect(x: 0, y: 25, width: 400, height: 900), step: 1))
        #expect(frame(.moveToRightHalf, (1, nil)) == CGRect(x: 400, y: 25, width: 800, height: 900))
        #expect(place(.moveToRightHalf, (2, nil))?.step == 0)
        #expect(frame(.moveToBottomHalf, (nil, nil)) == CGRect(x: 0, y: 475, width: 1200, height: 450))
    }

    @Test("코너는 너비만 순환하고 높이는 절반을 유지한다")
    func 코너() {
        #expect(frame(.moveToUpperLeft, (nil, nil)) == CGRect(x: 0, y: 25, width: 600, height: 450))
        #expect(frame(.moveToLowerRight, (0, nil)) == CGRect(x: 800, y: 475, width: 400, height: 450))
    }

    @Test("다음 1/3은 현재 칸 다음으로, 칸 밖이면 첫 칸으로 간다")
    func 삼분할() {
        #expect(place(.moveToNextThird, (nil, nil)) == .init(frame: CGRect(x: 0, y: 25, width: 400, height: 900), step: 0))
        let first = CGRect(x: 0, y: 25, width: 400, height: 900)
        #expect(frame(.moveToNextThird, (nil, first)) == CGRect(x: 400, y: 25, width: 400, height: 900))
        #expect(place(.moveToPreviousThird, (nil, first)) == .init(frame: CGRect(x: 800, y: 25, width: 400, height: 900), step: 2))
    }

    @Test("최소 너비 때문에 칸보다 넓어진 창도 다음 칸으로 넘어간다")
    func 최소너비삼분할() {
        let wideFirst = CGRect(x: 0, y: 25, width: 500, height: 900)
        #expect(frame(.moveToNextThird, (nil, wideFirst)) == CGRect(x: 400, y: 25, width: 400, height: 900))
        let wideLast = CGRect(x: 700, y: 25, width: 500, height: 900)
        #expect(frame(.moveToNextThird, (nil, wideLast)) == CGRect(x: 0, y: 25, width: 400, height: 900))
        #expect(frame(.moveToPreviousThird, (nil, wideLast)) == CGRect(x: 400, y: 25, width: 400, height: 900))
    }

    @Test("두 칸이 같은 자리로 밀리는 아주 넓은 창은 기억한 칸 번호로 다음 칸에 간다")
    func 아주넓은창() {
        // Minimum width 900: cells 1 and 2 both end up at x = 300 after fitting.
        let pushed = CGRect(x: 300, y: 25, width: 900, height: 900)
        #expect(place(.moveToNextThird, (1, pushed))?.step == 2)
        #expect(place(.moveToNextThird, (2, pushed))?.step == 0)
        #expect(place(.moveToPreviousThird, (2, pushed))?.step == 1)
    }

    @Test("세로 화면의 1/3은 행으로 나눈다")
    func 세로삼분할() {
        let portrait = CGRect(x: 0, y: 0, width: 900, height: 1500)
        let r = WindowLayout.placement(for: .moveToNextThird, in: .init(window: window, screen: portrait, previousStep: nil))
        #expect(r?.frame == CGRect(x: 0, y: 0, width: 900, height: 500))
    }

    @Test("가운데는 크기를 유지하고 화면보다 크면 화면에 맞춘다")
    func 가운데() {
        #expect(frame(.moveToCenter, (nil, nil)) == CGRect(x: 400, y: 325, width: 400, height: 300))
        let huge = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        #expect(frame(.moveToCenter, (nil, huge)) == screen)
        #expect(frame(.moveToFullscreen, (nil, nil)) == screen)
    }

    @Test("크기 증감은 화면을 넘지 않고 최소 크기 아래로 줄지 않는다")
    func 크기증감() {
        #expect(frame(.makeLarger, (nil, nil)) == CGRect(x: 40, y: 80, width: 520, height: 390))
        #expect(frame(.makeLarger, (nil, screen)) == screen)
        let small = CGRect(x: 100, y: 125, width: 250, height: 190)
        #expect(frame(.makeSmaller, (nil, small)) == CGRect(x: 105, y: 130, width: 240, height: 180))
    }

    @Test("화면 이동·기록 동작은 한 화면 계산으로 답하지 않는다")
    func 계산밖동작() {
        #expect(place(.moveToNextDisplay, (nil, nil)) == nil)
        #expect(place(.undoLastMove, (nil, nil)) == nil)
    }

    @Test("다른 화면으로 옮기면 상대 위치와 비율을 유지한다")
    func 화면이동() {
        let to = CGRect(x: 1200, y: -400, width: 2400, height: 1800)
        let moved = WindowLayout.moveProportionally(window, between: (screen, to))
        #expect(moved == CGRect(x: 1400, y: -200, width: 800, height: 600))
    }

    @Test("최소 크기 때문에 화면보다 큰 창은 화면 왼쪽 위에 붙는다")
    func 화면밖방지() {
        let big = CGRect(x: 900, y: 600, width: 1500, height: 1000)
        #expect(WindowLayout.fitInside(big, screen: screen) == CGRect(x: 0, y: 25, width: 1500, height: 1000))
        let edge = CGRect(x: 1000, y: 800, width: 400, height: 300)
        #expect(WindowLayout.fitInside(edge, screen: screen) == CGRect(x: 800, y: 625, width: 400, height: 300))
    }

    @Test("창이 가장 많이 걸친 화면을 고르고 화면 밖이면 첫 화면을 고른다")
    func 화면선택() {
        let right = CGRect(x: 1200, y: 0, width: 1920, height: 1080)
        #expect(WindowLayout.screenIndex(for: CGRect(x: 1100, y: 100, width: 400, height: 300), among: [screen, right]) == 1)
        #expect(WindowLayout.screenIndex(for: CGRect(x: -5000, y: 0, width: 10, height: 10), among: [screen, right]) == 0)
        #expect(WindowLayout.screenIndex(for: window, among: []) == nil)
    }
}
