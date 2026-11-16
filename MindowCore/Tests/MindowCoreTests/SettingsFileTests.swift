import CoreGraphics
import Foundation
import Testing
@testable import MindowCore

@Suite("설정 내보내기·가져오기")
struct SettingsFileTests {
    let id = "0193A2C4-7E1F-7B2A-9C3D-1E2F3A4B5C6D"
    let left = KeyBinding(carbonKeyCode: 123, carbonModifiers: 2304)

    func read(_ json: String, existing: LayoutSnapshots = LayoutSnapshots()) throws -> SettingsFile.ReadResult {
        try SettingsFile.read(Data(json.utf8), existing: existing)
    }

    var full: SettingsFile {
        SettingsFile(
            shortcuts: ["MoveToLeftHalf": left, "MoveToNextFourth": KeyBinding?.none, "TogglePause": KeyBinding(carbonKeyCode: 35, carbonModifiers: 6400),
                        "Layout_\(id)": KeyBinding(carbonKeyCode: 18, carbonModifiers: 6400)],
            gap: 8, dragSnap: true, showHUD: false, restoreOnDisplayChange: true, cycleOnRepeat: false,
            excludedApps: ExcludedApps(["com.riotgames.LeagueofLegends.GameClient"]),
            appRules: AppRules([AppRule(bundleID: "com.tinyspeck.slackmacgap", action: .moveToBottomHalf, display: 1)]),
            layouts: LayoutSnapshots([LayoutSnapshot(id: id, name: "코딩", windows: [
                LayoutSnapshot.Window(bundleID: "com.stablyso.orca", title: "mindow", index: 0, display: 0,
                                      frame: CGRect(x: 0, y: 25, width: 1720, height: 1415), screen: CGSize(width: 1720, height: 1415)),
            ])])
        )
    }

    @Test("내보낸 파일을 다시 읽으면 같은 설정이고 건너뛴 항목이 없다")
    func 왕복() throws {
        let result = try SettingsFile.read(full.json(), existing: LayoutSnapshots())
        #expect(result.settings == full)
        #expect(result.skipped.isEmpty)
    }

    @Test("명세의 모양으로 쓴다: 형식·버전, 단축키 없음은 null, 키 정렬")
    func 모양() throws {
        let text = try #require(String(data: full.json(), encoding: .utf8))
        #expect(text.contains(#""format" : "mindow-settings""#))
        #expect(text.contains(#""version" : 1"#))
        #expect(text.contains(#""MoveToNextFourth" : null"#))
        #expect(text.contains(#""MoveToLeftHalf" : {"#))
        #expect(text.contains(#""gap" : 8"#))
        let object = try #require(try JSONSerialization.jsonObject(with: full.json()) as? [String: Any])
        #expect(Set(object.keys) == ["format", "version", "shortcuts", "gap", "dragSnap", "showHUD", "restoreOnDisplayChange",
                                    "cycleOnRepeat", "excludedApps", "appRules", "layouts"])
        let keys = ["appRules", "cycleOnRepeat", "dragSnap", "excludedApps", "format", "gap", "layouts"]
        let positions = keys.compactMap { text.range(of: "\"\($0)\"")?.lowerBound }
        #expect(positions == positions.sorted())
    }

    @Test("명세 예시 파일을 그대로 읽는다")
    func 명세예시() throws {
        let result = try read("""
        {
          "format": "mindow-settings",
          "version": 1,
          "shortcuts": {
            "MoveToLeftHalf": { "carbonKeyCode": 123, "carbonModifiers": 2304 },
            "MoveToNextFourth": null
          },
          "gap": 8,
          "dragSnap": true,
          "showHUD": true,
          "restoreOnDisplayChange": true,
          "cycleOnRepeat": true,
          "excludedApps": ["com.riotgames.LeagueofLegends.GameClient"],
          "appRules": [{ "bundleID": "com.tinyspeck.slackmacgap", "action": "MoveToBottomHalf", "display": 1 }],
          "layouts": []
        }
        """)
        #expect(result.skipped.isEmpty)
        #expect(result.settings.shortcuts == ["MoveToLeftHalf": left, "MoveToNextFourth": KeyBinding?.none])
        #expect(result.settings.gap == 8)
        #expect(result.settings.appRules?.rules == [AppRule(bundleID: "com.tinyspeck.slackmacgap", action: .moveToBottomHalf, display: 1)])
        #expect(result.settings.layouts == LayoutSnapshots())
    }

    @Test("모르는 키·단축키 이름·동작은 건너뛰고 목록에 남기며 나머지는 읽는다")
    func 모르는항목() throws {
        let result = try read("""
        {"format": "mindow-settings", "version": 1, "showMenuBarIcon": true, "theme": "dark",
         "shortcuts": {"MoveToMars": null, "MoveToLeftHalf": null, "Layout_\(id)": null, "Layout_nope": null},
         "appRules": [{"bundleID": "a", "action": "MoveToMars"}, {"bundleID": "b", "action": "MoveToLeftHalf"}]}
        """)
        #expect(result.skipped == [
            "showMenuBarIcon: unknown setting", "theme: unknown setting",
            "appRules: a",
            "shortcuts.Layout_\(id): unknown shortcut", "shortcuts.Layout_nope: unknown shortcut", "shortcuts.MoveToMars: unknown shortcut",
        ])
        #expect(result.settings.shortcuts == ["MoveToLeftHalf": KeyBinding?.none])
        #expect(result.settings.appRules?.rules == [AppRule(bundleID: "b", action: .moveToLeftHalf)])
    }

    @Test("레이아웃 단축키는 파일에 레이아웃이 있으면 파일의 것, 없으면 지금 있는 레이아웃만 받는다")
    func 레이아웃단축키() throws {
        let existing = LayoutSnapshots([LayoutSnapshot(id: id, name: "코딩", windows: [])])
        let shortcut = #""shortcuts": {"Layout_\#(id)": {"carbonKeyCode": 18, "carbonModifiers": 6400}}"#
        let kept = try read(#"{"format": "mindow-settings", "version": 1, \#(shortcut)}"#, existing: existing)
        #expect(kept.skipped.isEmpty)
        #expect(kept.settings.shortcuts["Layout_\(id)"] == KeyBinding(carbonKeyCode: 18, carbonModifiers: 6400))
        let replaced = try read(#"{"format": "mindow-settings", "version": 1, "layouts": [], \#(shortcut)}"#, existing: existing)
        #expect(replaced.skipped == ["shortcuts.Layout_\(id): unknown shortcut"])
    }

    @Test("항목마다 타입이 틀리면 그 항목만 이유와 함께 건너뛴다")
    func 타입() throws {
        let result = try read("""
        {"format": "mindow-settings", "version": 1, "gap": "8", "dragSnap": 1, "showHUD": "yes", "cycleOnRepeat": false,
         "excludedApps": ["a", 3, "b"], "appRules": {}, "layouts": [{"id": "x"}, {"id": "\(id)", "name": "코딩", "windows": [3]}],
         "shortcuts": {"MoveToLeftHalf": {"carbonKeyCode": "123", "carbonModifiers": 2304}, "MoveToRightHalf": true, "MoveToTopHalf": {"carbonKeyCode": 126, "carbonModifiers": 2304}}}
        """)
        #expect(result.skipped == [
            "gap: not a number from 0 to 32",
            "dragSnap: not true or false", "showHUD: not true or false",
            "excludedApps: 1 entries that aren't text",
            "appRules: not a list",
            "layouts: an entry that isn't valid", "layouts: 1 windows of 코딩",
            "shortcuts.MoveToLeftHalf: not a shortcut or null", "shortcuts.MoveToRightHalf: not a shortcut or null",
        ])
        #expect(result.settings.gap == nil && result.settings.dragSnap == nil && result.settings.appRules == nil)
        #expect(result.settings.cycleOnRepeat == false)
        #expect(result.settings.excludedApps == ExcludedApps(["a", "b"]))
        #expect(result.settings.layouts?.layouts.map(\.name) == ["코딩"])
        #expect(result.settings.shortcuts == ["MoveToTopHalf": KeyBinding(carbonKeyCode: 126, carbonModifiers: 2304)])
        #expect(try read(#"{"format": "mindow-settings", "version": 1, "gap": 40}"#).skipped == ["gap: not a number from 0 to 32"])
        #expect(try read(#"{"format": "mindow-settings", "version": 1, "shortcuts": []}"#).skipped == ["shortcuts: not an object"])
    }

    @Test("버전이 지금보다 크면 읽지 않고, 형식이 다르거나 JSON이 아니면 거절한다")
    func 거절() {
        #expect(throws: SettingsFile.ReadError.newerVersion(2)) { try read(#"{"format": "mindow-settings", "version": 2}"#) }
        #expect(throws: SettingsFile.ReadError.notSettingsFile) { try read(#"{"format": "spectacle", "version": 1}"#) }
        #expect(throws: SettingsFile.ReadError.notSettingsFile) { try read(#"{"format": "mindow-settings"}"#) }
        #expect(throws: SettingsFile.ReadError.notSettingsFile) { try read(#"{"format": "mindow-settings", "version": true}"#) }
        #expect(throws: SettingsFile.ReadError.notSettingsFile) { try read(#"[]"#) }
        #expect(throws: SettingsFile.ReadError.notJSON) { try read("not json") }
    }

    @Test("파일에 없는 항목은 바꾸지 않고, 다른 값만 바뀔 목록에 오른다")
    func 바뀔목록() throws {
        let current = full
        var file = SettingsFile(shortcuts: ["MoveToLeftHalf": left, "MoveToNextFourth": KeyBinding(carbonKeyCode: 124, carbonModifiers: 6656)])
        file.gap = 8
        file.showHUD = true
        file.excludedApps = ExcludedApps()
        #expect(file.changes(from: current) == [
            .value("showHUD", from: "off", to: "on"),
            .value("excludedApps", from: "com.riotgames.LeagueofLegends.GameClient", to: "none"),
            .shortcut("MoveToNextFourth", from: nil, to: KeyBinding(carbonKeyCode: 124, carbonModifiers: 6656)),
        ])
        #expect(full.changes(from: current).isEmpty)
        #expect(SettingsFile().changes(from: current).isEmpty)
    }
}
