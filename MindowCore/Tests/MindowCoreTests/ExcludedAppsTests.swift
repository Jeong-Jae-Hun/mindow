import Testing
@testable import MindowCore

@Suite("앱별 단축키 제외")
struct ExcludedAppsTests {
    let game = "com.riotgames.LeagueofLegends.GameClient"
    let slack = "com.tinyspeck.slackmacgap"

    @Test("일시 정지도 아니고 제외 앱도 앞에 없을 때만 동작 단축키가 켜진다")
    func 켜짐규칙() {
        let apps = ExcludedApps([game])
        #expect(apps.allowsActionShortcuts(paused: false, frontmost: slack))
        #expect(!apps.allowsActionShortcuts(paused: false, frontmost: game))
        #expect(!apps.allowsActionShortcuts(paused: true, frontmost: slack))
        #expect(!apps.allowsActionShortcuts(paused: true, frontmost: game))
    }

    @Test("앞 앱을 모르면(nil) 제외로 보지 않고, 빈 목록은 아무것도 끄지 않는다")
    func 모르는앞앱() {
        #expect(ExcludedApps([game]).allowsActionShortcuts(paused: false, frontmost: nil))
        #expect(ExcludedApps().allowsActionShortcuts(paused: false, frontmost: game))
    }

    @Test("추가는 이미 있거나 빈 값이면 바뀌지 않았다고 알리고, 순서를 지킨다")
    func 추가() {
        var apps = ExcludedApps([game])
        let added = apps.add(slack)
        let repeated = apps.add(game)
        let empty = apps.add("")
        #expect(added && !repeated && !empty)
        #expect(apps.bundleIDs == [game, slack])
    }

    @Test("삭제하면 그 앱만 빠지고, 없는 앱 삭제는 그대로다")
    func 삭제() {
        var apps = ExcludedApps([game, slack])
        apps.remove(game)
        #expect(apps.bundleIDs == [slack])
        apps.remove("com.example.none")
        #expect(apps.bundleIDs == [slack])
    }

    @Test("저장값에 중복·빈 값이 있어도 한 번씩 첫 순서대로 읽는다")
    func 정규화() {
        #expect(ExcludedApps([slack, "", game, slack]).bundleIDs == [slack, game])
    }
}
