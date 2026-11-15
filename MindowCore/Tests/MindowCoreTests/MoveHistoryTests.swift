import CoreGraphics
import Testing
@testable import MindowCore

@Suite("창별 되돌리기")
struct MoveHistoryTests {
    let a = CGRect(x: 0, y: 0, width: 100, height: 100)
    let b = CGRect(x: 50, y: 0, width: 100, height: 100)

    @Test("되돌리면 이전 위치, 다시 하면 되돌리기 전 위치가 나온다")
    func 되돌리기() {
        var history = MoveHistory<Int>()
        history.record(a, for: 1)
        #expect(history.undo(for: 1, current: b) == a)
        #expect(history.redo(for: 1, current: a) == b)
        #expect(history.redo(for: 1, current: b) == nil)
    }

    @Test("창마다 기록이 따로 쌓인다")
    func 창별() {
        var history = MoveHistory<Int>()
        history.record(a, for: 1)
        #expect(history.undo(for: 2, current: b) == nil)
    }

    @Test("새로 옮기면 다시 하기 기록이 지워진다")
    func 새이동() {
        var history = MoveHistory<Int>()
        history.record(a, for: 1)
        _ = history.undo(for: 1, current: b)
        history.record(a, for: 1)
        #expect(history.redo(for: 1, current: a) == nil)
    }

    @Test("기록은 최근 것만 한도까지 남는다")
    func 한도() {
        var history = MoveHistory<Int>()
        for i in 0...MoveHistory<Int>.limit {
            history.record(CGRect(x: CGFloat(i), y: 0, width: 1, height: 1), for: 1)
        }
        var count = 0
        while history.undo(for: 1, current: .zero) != nil { count += 1 }
        #expect(count == MoveHistory<Int>.limit)
    }
}
