import CoreGraphics
import Testing
@testable import MindowCore

@Suite("드래그 스냅 영역")
struct SnapZoneTests {
    let laptop = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func onLaptop(_ x: CGFloat, _ y: CGFloat) -> SnapZone.Target? {
        SnapZone.target(at: CGPoint(x: x, y: y), screens: [laptop])
    }

    func onThree(_ x: CGFloat, _ y: CGFloat) -> SnapZone.Target? {
        SnapZone.target(at: CGPoint(x: x, y: y), screens: [laptop, portrait, wide])
    }

    @Test("왼쪽·오른쪽 가장자리 6pt 안은 절반, 위쪽은 전체다")
    func 가장자리() {
        #expect(onLaptop(0, 450) == .init(action: .moveToLeftHalf, screen: 0))
        #expect(onLaptop(5, 450) == .init(action: .moveToLeftHalf, screen: 0))
        #expect(onLaptop(1439, 450) == .init(action: .moveToRightHalf, screen: 0))
        #expect(onLaptop(1434, 450) == .init(action: .moveToRightHalf, screen: 0))
        #expect(onLaptop(720, 0) == .init(action: .moveToFullscreen, screen: 0))
        #expect(onLaptop(720, 5) == .init(action: .moveToFullscreen, screen: 0))
    }

    @Test("가장자리에서 6pt 넘게 떨어지면 아무것도 아니다")
    func 가장자리밖() {
        #expect(onLaptop(6, 450) == nil)
        #expect(onLaptop(1433, 450) == nil)
        #expect(onLaptop(720, 6) == nil)
        #expect(onLaptop(720, 450) == nil)
    }

    @Test("아래쪽 가장자리는 아무것도 아니다")
    func 아래쪽() {
        #expect(onLaptop(720, 899) == nil)
        #expect(onLaptop(720, 894) == nil)
    }

    @Test("네 모서리 20pt 정사각형은 가장자리보다 먼저 코너가 된다")
    func 모서리() {
        #expect(onLaptop(0, 0) == .init(action: .moveToUpperLeft, screen: 0))
        #expect(onLaptop(19, 19) == .init(action: .moveToUpperLeft, screen: 0))
        #expect(onLaptop(1439, 3) == .init(action: .moveToUpperRight, screen: 0))
        #expect(onLaptop(2, 899) == .init(action: .moveToLowerLeft, screen: 0))
        #expect(onLaptop(1439, 880) == .init(action: .moveToLowerRight, screen: 0))
        // Inside the corner square but away from both edges: the corner still wins.
        #expect(onLaptop(15, 15) == .init(action: .moveToUpperLeft, screen: 0))
    }

    @Test("모서리 정사각형 바로 바깥은 그 가장자리 동작이다")
    func 모서리경계() {
        #expect(onLaptop(20, 2) == .init(action: .moveToFullscreen, screen: 0))
        #expect(onLaptop(2, 20) == .init(action: .moveToLeftHalf, screen: 0))
        #expect(onLaptop(1437, 879) == .init(action: .moveToRightHalf, screen: 0))
        #expect(onLaptop(1419, 2) == .init(action: .moveToFullscreen, screen: 0))
    }

    // Primary laptop at the origin, a portrait screen on the left raised above it,
    // and a landscape screen on the right set lower, as AX reports them.
    let portrait = CGRect(x: -1080, y: -500, width: 1080, height: 1920)
    let wide = CGRect(x: 1440, y: 200, width: 2560, height: 1440)

    @Test("여러 화면에서는 커서가 있는 화면과 그 순번을 고른다")
    func 여러화면() {
        #expect(onThree(-1080, 300) == .init(action: .moveToLeftHalf, screen: 1))
        #expect(onThree(-540, -500) == .init(action: .moveToFullscreen, screen: 1))
        #expect(onThree(-1080, 1419) == .init(action: .moveToLowerLeft, screen: 1))
        #expect(onThree(3999, 200) == .init(action: .moveToUpperRight, screen: 2))
        #expect(onThree(2700, 202) == .init(action: .moveToFullscreen, screen: 2))
        #expect(onThree(3000, 1639) == nil)
    }

    @Test("두 화면이 맞닿은 선에서는 커서가 있는 쪽 화면의 가장자리가 된다")
    func 맞닿은선() {
        #expect(onThree(-1, 450) == .init(action: .moveToRightHalf, screen: 1))
        #expect(onThree(0, 450) == .init(action: .moveToLeftHalf, screen: 0))
        #expect(onThree(1439, 450) == .init(action: .moveToRightHalf, screen: 0))
        #expect(onThree(1440, 450) == .init(action: .moveToLeftHalf, screen: 2))
    }

    @Test("어느 화면에도 없는 점(화면 사이 빈 곳, 끝선 바깥)은 아무것도 아니다")
    func 화면밖() {
        // Right of the laptop, above the lower right screen.
        #expect(onThree(1500, 100) == nil)
        // Below the laptop's last row, left of the right screen.
        #expect(onThree(700, 900) == nil)
        #expect(onThree(4000, 300) == nil)
        #expect(SnapZone.target(at: .zero, screens: []) == nil)
    }

    @Test("드래그 스냅 미리보기와 배치는 순환 없이 첫 단계에 간격을 적용한 사각형이다")
    func 미리보기사각형() throws {
        let visible = CGRect(x: -1080, y: -475, width: 1080, height: 1895)
        let snap = try #require(onThree(-1080, 300))
        let context = WindowLayout.Context(window: .init(x: -900, y: 0, width: 500, height: 400),
                                           screen: visible, previousStep: nil, gap: 8)
        let placement = try #require(WindowLayout.placement(for: snap.action, in: context))
        #expect(placement == .init(frame: CGRect(x: -1072, y: -467, width: 528, height: 1879), step: 0))
    }
}
