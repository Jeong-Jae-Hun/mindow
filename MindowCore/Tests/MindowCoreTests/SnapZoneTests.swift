import CoreGraphics
import Testing
@testable import MindowCore

@Suite("드래그 스냅 영역")
struct SnapZoneTests {
    let laptop = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func target(_ x: CGFloat, _ y: CGFloat, _ screens: [CGRect]) -> SnapZone.Target? {
        SnapZone.target(at: CGPoint(x: x, y: y), screens: screens)
    }

    @Test("왼쪽·오른쪽 가장자리 6pt 안은 절반, 위쪽은 전체다")
    func 가장자리() {
        #expect(target(0, 450, [laptop]) == .init(action: .moveToLeftHalf, screen: 0))
        #expect(target(5, 450, [laptop]) == .init(action: .moveToLeftHalf, screen: 0))
        #expect(target(1439, 450, [laptop]) == .init(action: .moveToRightHalf, screen: 0))
        #expect(target(1434, 450, [laptop]) == .init(action: .moveToRightHalf, screen: 0))
        #expect(target(720, 0, [laptop]) == .init(action: .moveToFullscreen, screen: 0))
        #expect(target(720, 5, [laptop]) == .init(action: .moveToFullscreen, screen: 0))
    }

    @Test("가장자리에서 6pt 넘게 떨어지면 아무것도 아니다")
    func 가장자리밖() {
        #expect(target(6, 450, [laptop]) == nil)
        #expect(target(1433, 450, [laptop]) == nil)
        #expect(target(720, 6, [laptop]) == nil)
        #expect(target(720, 450, [laptop]) == nil)
    }

    @Test("아래쪽 가장자리는 아무것도 아니다")
    func 아래쪽() {
        #expect(target(720, 899, [laptop]) == nil)
        #expect(target(720, 894, [laptop]) == nil)
    }

    @Test("네 모서리 20pt 정사각형은 가장자리보다 먼저 코너가 된다")
    func 모서리() {
        #expect(target(0, 0, [laptop]) == .init(action: .moveToUpperLeft, screen: 0))
        #expect(target(19, 19, [laptop]) == .init(action: .moveToUpperLeft, screen: 0))
        #expect(target(1439, 3, [laptop]) == .init(action: .moveToUpperRight, screen: 0))
        #expect(target(2, 899, [laptop]) == .init(action: .moveToLowerLeft, screen: 0))
        #expect(target(1439, 880, [laptop]) == .init(action: .moveToLowerRight, screen: 0))
        // Inside the corner square but away from both edges: the corner still wins.
        #expect(target(15, 15, [laptop]) == .init(action: .moveToUpperLeft, screen: 0))
    }

    @Test("모서리 정사각형 바로 바깥은 그 가장자리 동작이다")
    func 모서리경계() {
        #expect(target(20, 2, [laptop]) == .init(action: .moveToFullscreen, screen: 0))
        #expect(target(2, 20, [laptop]) == .init(action: .moveToLeftHalf, screen: 0))
        #expect(target(1437, 879, [laptop]) == .init(action: .moveToRightHalf, screen: 0))
        #expect(target(1419, 2, [laptop]) == .init(action: .moveToFullscreen, screen: 0))
    }

    // Primary laptop at the origin, a portrait screen on the left raised above it,
    // and a landscape screen on the right set lower, as AX reports them.
    let portrait = CGRect(x: -1080, y: -500, width: 1080, height: 1920)
    let wide = CGRect(x: 1440, y: 200, width: 2560, height: 1440)
    var three: [CGRect] { [laptop, portrait, wide] }

    @Test("여러 화면에서는 커서가 있는 화면과 그 순번을 고른다")
    func 여러화면() {
        #expect(target(-1080, 300, three) == .init(action: .moveToLeftHalf, screen: 1))
        #expect(target(-540, -500, three) == .init(action: .moveToFullscreen, screen: 1))
        #expect(target(-1080, 1419, three) == .init(action: .moveToLowerLeft, screen: 1))
        #expect(target(3999, 200, three) == .init(action: .moveToUpperRight, screen: 2))
        #expect(target(2700, 202, three) == .init(action: .moveToFullscreen, screen: 2))
        #expect(target(3000, 1639, three) == nil)
    }

    @Test("두 화면이 맞닿은 선에서는 커서가 있는 쪽 화면의 가장자리가 된다")
    func 맞닿은선() {
        #expect(target(-1, 450, three) == .init(action: .moveToRightHalf, screen: 1))
        #expect(target(0, 450, three) == .init(action: .moveToLeftHalf, screen: 0))
        #expect(target(1439, 450, three) == .init(action: .moveToRightHalf, screen: 0))
        #expect(target(1440, 450, three) == .init(action: .moveToLeftHalf, screen: 2))
    }

    @Test("어느 화면에도 없는 점(화면 사이 빈 곳, 끝선 바깥)은 아무것도 아니다")
    func 화면밖() {
        // Right of the laptop, above the lower right screen.
        #expect(target(1500, 100, three) == nil)
        // Below the laptop's last row, left of the right screen.
        #expect(target(700, 900, three) == nil)
        #expect(target(4000, 300, three) == nil)
        #expect(target(0, 0, []) == nil)
    }

    @Test("드래그 스냅 미리보기와 배치는 순환 없이 첫 단계에 간격을 적용한 사각형이다")
    func 미리보기사각형() throws {
        let visible = CGRect(x: -1080, y: -475, width: 1080, height: 1895)
        let snap = try #require(target(-1080, 300, three))
        let context = WindowLayout.Context(window: .init(x: -900, y: 0, width: 500, height: 400),
                                           screen: visible, previousStep: nil, gap: 8)
        let placement = try #require(WindowLayout.placement(for: snap.action, in: context))
        #expect(placement == .init(frame: CGRect(x: -1072, y: -467, width: 528, height: 1879), step: 0))
    }
}
