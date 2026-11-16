import CoreGraphics
import Testing
@testable import MindowCore

@Suite("앱별 자동 배치")
struct AppRulesTests {
    let slack = "com.tinyspeck.slackmacgap"
    let orca = "com.stablyso.orca"
    let left = CGRect(x: 0, y: 25, width: 1200, height: 900)
    let right = CGRect(x: 1200, y: 0, width: 1600, height: 1000)
    let window = CGRect(x: 100, y: 125, width: 400, height: 300)

    @Test("저장값을 읽고 그대로 다시 쓰며, 화면이 없으면 키도 없다")
    func 왕복() {
        let stored: [[String: Any]] = [
            ["bundleID": slack, "action": "MoveToBottomHalf", "display": 1],
            ["bundleID": orca, "action": "MoveToLeftHalf"],
        ]
        let rules = AppRules(plist: stored)
        #expect(rules.rules == [
            AppRule(bundleID: slack, action: .moveToBottomHalf, display: 1),
            AppRule(bundleID: orca, action: .moveToLeftHalf),
        ])
        #expect(AppRules(plist: rules.plist) == rules)
        #expect(rules.plist[1]["display"] == nil)
    }

    @Test("모르는 동작·규칙에 못 쓰는 동작·잘못된 화면·빈 앱은 그 규칙만 건너뛴다")
    func 잘못된값() {
        let stored: [Any] = [
            ["bundleID": slack, "action": "MoveToMars"],
            ["bundleID": slack, "action": "UndoLastMove"],
            ["bundleID": slack, "action": "MoveToNextDisplay"],
            ["bundleID": slack, "action": "SplitWithPrevious"],
            ["bundleID": slack, "action": "MoveToLeftHalf", "display": -1],
            ["bundleID": slack, "action": "MoveToLeftHalf", "display": "1"],
            ["bundleID": "", "action": "MoveToLeftHalf"],
            ["action": "MoveToLeftHalf"],
            "MoveToLeftHalf",
            ["bundleID": orca, "action": "MoveToFullscreen", "display": 0],
        ]
        #expect(AppRules(plist: stored).rules == [AppRule(bundleID: orca, action: .moveToFullscreen, display: 0)])
        #expect(AppRules(plist: nil).rules.isEmpty)
        #expect(AppRules(plist: "nonsense").rules.isEmpty)
    }

    @Test("한 앱에 규칙이 둘이면 첫 규칙만 남는다")
    func 중복() {
        let rules = AppRules([AppRule(bundleID: slack, action: .moveToTopHalf), AppRule(bundleID: slack, action: .moveToBottomHalf)])
        #expect(rules.rules == [AppRule(bundleID: slack, action: .moveToTopHalf)])
        #expect(rules.rule(for: slack)?.action == .moveToTopHalf)
        #expect(rules.rule(for: orca) == nil && rules.rule(for: nil) == nil)
    }

    @Test("추가는 왼쪽 절반·지금 화면으로 시작하고, 이미 있거나 빈 앱이면 바뀌지 않았다고 알린다")
    func 추가() {
        var rules = AppRules()
        let added = rules.add(slack)
        let repeated = rules.add(slack)
        let empty = rules.add("")
        #expect(added && !repeated && !empty)
        #expect(rules.rules == [AppRule(bundleID: slack, action: .moveToLeftHalf)])
    }

    @Test("수정은 같은 앱 규칙만 바꾸고, 삭제는 그 앱만 뺀다")
    func 수정삭제() {
        var rules = AppRules([AppRule(bundleID: slack, action: .moveToLeftHalf), AppRule(bundleID: orca, action: .moveToLeftHalf)])
        rules.update(AppRule(bundleID: slack, action: .moveToRightHalf, display: 1))
        rules.update(AppRule(bundleID: "com.example.none", action: .moveToRightHalf))
        #expect(rules.rules.map(\.action) == [.moveToRightHalf, .moveToLeftHalf])
        #expect(rules.rules.count == 2)
        rules.remove(slack)
        #expect(rules.rules.map(\.bundleID) == [orca])
    }

    @Test("규칙에 쓸 수 있는 동작은 기록·화면 이동·나란히를 뺀 전부다")
    func 동작목록() {
        #expect(!AppRule.actions.contains(.undoLastMove))
        #expect(!AppRule.actions.contains(.redoLastMove))
        #expect(!AppRule.actions.contains(.moveToNextDisplay))
        #expect(!AppRule.actions.contains(.moveToPreviousDisplay))
        #expect(!AppRule.actions.contains(.splitWithPrevious))
        #expect(AppRule.actions.count == WindowAction.allCases.count - 5)
    }

    @Test("화면을 고르면 그 화면에, 없으면 창이 열린 화면에 첫 단계 배치를 간격과 함께 한다")
    func 배치() throws {
        let screens = [left, right]
        let chosen = try #require(AppRule(bundleID: slack, action: .moveToBottomHalf, display: 1).placement(for: window, among: screens, gap: 0))
        #expect(chosen.screen == 1)
        #expect(chosen.frame == CGRect(x: 1200, y: 500, width: 1600, height: 500))
        let own = try #require(AppRule(bundleID: slack, action: .moveToLeftHalf).placement(for: window, among: screens, gap: 0))
        #expect(own.screen == 0)
        #expect(own.frame == CGRect(x: 0, y: 25, width: 600, height: 900))
        let gapped = try #require(AppRule(bundleID: slack, action: .moveToLeftHalf).placement(for: window, among: screens, gap: 8))
        #expect(gapped.frame == CGRect(x: 8, y: 33, width: 588, height: 884))
    }

    @Test("연결 안 된 화면 번호는 창이 열린 화면으로 대신하고, 화면이 없으면 배치하지 않는다")
    func 없는화면() throws {
        let onRight = CGRect(x: 1500, y: 100, width: 400, height: 300)
        let fallback = try #require(AppRule(bundleID: slack, action: .moveToLeftHalf, display: 2).placement(for: onRight, among: [left, right], gap: 0))
        #expect(fallback.screen == 1)
        let huge = AppRules(plist: [["bundleID": slack, "action": "MoveToLeftHalf", "display": Int.max]])
        #expect(huge.rule(for: slack)?.placement(for: onRight, among: [left, right], gap: 0)?.screen == 1)
        #expect(AppRule(bundleID: slack, action: .moveToLeftHalf).placement(for: window, among: [], gap: 0) == nil)
    }
}
