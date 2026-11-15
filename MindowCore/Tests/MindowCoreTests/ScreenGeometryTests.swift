import CoreGraphics
import Testing
@testable import MindowCore

@Suite("화면 좌표 변환")
struct ScreenGeometryTests {
    let primaryHeight: CGFloat = 1117

    @Test("주 화면 왼쪽 아래 창은 AX에서 화면 아래쪽에 놓인다")
    func 주화면() {
        let cocoa = CGRect(x: 0, y: 0, width: 800, height: 600)
        #expect(ScreenGeometry.flipped(cocoa, primaryScreenHeight: primaryHeight)
            == CGRect(x: 0, y: 517, width: 800, height: 600))
    }

    @Test("주 화면 위에 놓인 보조 화면은 AX에서 y가 음수다")
    func 위쪽보조화면() {
        let cocoa = CGRect(x: 0, y: 1117, width: 2560, height: 1440)
        #expect(ScreenGeometry.flipped(cocoa, primaryScreenHeight: primaryHeight)
            == CGRect(x: 0, y: -1440, width: 2560, height: 1440))
    }

    @Test("왼쪽에 놓인 보조 화면은 x를 그대로 둔다")
    func 왼쪽보조화면() {
        let cocoa = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        #expect(ScreenGeometry.flipped(cocoa, primaryScreenHeight: primaryHeight)
            == CGRect(x: -1920, y: 237, width: 1920, height: 1080))
    }

    @Test("두 번 변환하면 원래 사각형으로 돌아온다")
    func 왕복() {
        let rect = CGRect(x: 123, y: -456, width: 789, height: 321)
        let back = ScreenGeometry.flipped(
            ScreenGeometry.flipped(rect, primaryScreenHeight: primaryHeight),
            primaryScreenHeight: primaryHeight
        )
        #expect(back == rect)
    }
}
