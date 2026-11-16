import CoreGraphics
import Testing
@testable import MindowCore

@Suite("전체 화면 토글 기억")
struct MaximizeMemoryTests {
    let full = CGRect(x: 0, y: 25, width: 1200, height: 900)
    let small = CGRect(x: 100, y: 125, width: 400, height: 300)
    let half = CGRect(x: 0, y: 25, width: 600, height: 900)

    @Test("전체 화면 상태에서 다시 누르면 전체 직전 위치가 나오고, 잊은 뒤에는 없다")
    func 토글() {
        var memory = MaximizeMemory<Int>()
        memory.remember(small, for: 1)
        #expect(memory.restoreFrame(for: 1, current: full, fullscreen: full) == small)
        memory.forget(1)
        #expect(memory.restoreFrame(for: 1, current: full, fullscreen: full) == nil)
    }

    @Test("앱이 반올림해 몇 pt 어긋난 전체 화면도 전체 상태로 본다")
    func 허용오차() {
        var memory = MaximizeMemory<Int>()
        memory.remember(small, for: 1)
        #expect(memory.restoreFrame(for: 1, current: full.insetBy(dx: 1, dy: 1), fullscreen: full) == small)
    }

    @Test("기억이 없으면 복원할 위치가 없다")
    func 기억없음() {
        let memory = MaximizeMemory<Int>()
        #expect(memory.restoreFrame(for: 1, current: full, fullscreen: full) == nil)
    }

    @Test("전체 화면에서 다른 곳으로 옮긴 창은 복원하지 않고, 다시 전체로 가면 기억을 덮어쓴다")
    func 덮어쓰기() {
        var memory = MaximizeMemory<Int>()
        memory.remember(small, for: 1)
        #expect(memory.restoreFrame(for: 1, current: half, fullscreen: full) == nil)
        memory.remember(half, for: 1)
        #expect(memory.restoreFrame(for: 1, current: full, fullscreen: full) == half)
    }

    @Test("창마다 기억이 따로 있다")
    func 창별() {
        var memory = MaximizeMemory<Int>()
        memory.remember(small, for: 1)
        memory.remember(half, for: 2)
        #expect(memory.restoreFrame(for: 2, current: full, fullscreen: full) == half)
        memory.forget(2)
        #expect(memory.restoreFrame(for: 1, current: full, fullscreen: full) == small)
    }
}
