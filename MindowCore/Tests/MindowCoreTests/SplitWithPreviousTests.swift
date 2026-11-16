import CoreGraphics
import Testing
@testable import MindowCore

@Suite("직전 창과 나란히")
struct SplitWithPreviousTests {
    let screen = CGRect(x: 0, y: 25, width: 1200, height: 900)
    let left = CGRect(x: 0, y: 25, width: 600, height: 900)
    let right = CGRect(x: 600, y: 25, width: 600, height: 900)
    let window = CGRect(x: 100, y: 125, width: 400, height: 300)

    @Test("지금 창은 왼쪽 절반, 직전 창은 오른쪽 절반으로 간다")
    func 처음() throws {
        let frames = try #require(SplitWithPrevious.frames(of: (window, window), on: (screen, 0)))
        #expect(frames.current == left)
        #expect(frames.previous == right)
    }

    @Test("둘 다 그 자리에 있으면 좌우를 맞바꾸고, 맞바꾼 자리에서 다시 누르면 되돌아온다")
    func 맞바꿈() throws {
        let swapped = try #require(SplitWithPrevious.frames(of: (left, right), on: (screen, 0)))
        #expect(swapped.current == right)
        #expect(swapped.previous == left)
        let back = try #require(SplitWithPrevious.frames(of: (swapped.current, swapped.previous), on: (screen, 0)))
        #expect(back.current == left)
        #expect(back.previous == right)
    }

    @Test("한쪽만 제자리면 맞바꾸지 않고, 앱이 몇 pt 어긋나게 받은 자리는 제자리로 본다")
    func 맞바꿈판정() throws {
        let one = try #require(SplitWithPrevious.frames(of: (left, window), on: (screen, 0)))
        #expect(one.current == left)
        let nudged = try #require(SplitWithPrevious.frames(of: (left.insetBy(dx: 1, dy: 1), right), on: (screen, 0)))
        #expect(nudged.current == right)
    }

    @Test("간격이 있으면 절반 배치와 같은 간격을 두고, 그 자리에서도 맞바꾼다")
    func 간격() throws {
        let gapped = (left: CGRect(x: 8, y: 33, width: 588, height: 884), right: CGRect(x: 604, y: 33, width: 588, height: 884))
        let frames = try #require(SplitWithPrevious.frames(of: (window, window), on: (screen, 8)))
        #expect(frames.current == gapped.left)
        #expect(frames.previous == gapped.right)
        let swapped = try #require(SplitWithPrevious.frames(of: (gapped.left, gapped.right), on: (screen, 8)))
        #expect(swapped.current == gapped.right)
        #expect(swapped.previous == gapped.left)
    }
}

@Suite("직전 앱 추적")
struct RecentAppsTests {
    @Test("지금 앞 앱의 직전 앱은 그 바로 전에 활성화된 다른 앱이다")
    func 직전() {
        var apps = RecentApps<String>()
        apps.activated("a")
        apps.activated("b")
        #expect(apps.last == "b")
        #expect(apps.previous(before: "b") == "a")
    }

    @Test("같은 앱이 다시 활성화되면 순서가 그대로이고, 오가면 서로가 직전 앱이다")
    func 재활성화() {
        var apps = RecentApps<String>()
        apps.activated("a")
        apps.activated("b")
        apps.activated("b")
        #expect(apps.previous(before: "b") == "a")
        apps.activated("a")
        #expect(apps.previous(before: "a") == "b")
    }

    @Test("대상이 아직 기록되지 않았으면 마지막 앱이 직전 앱이고, 대상 자신은 나오지 않는다")
    func 대상() {
        var apps = RecentApps<String>()
        apps.activated("a")
        #expect(apps.previous(before: "c") == "a")
        #expect(apps.previous(before: "a") == nil)
        #expect(RecentApps<String>().previous(before: "a") == nil)
    }
}
