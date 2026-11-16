import CoreGraphics
import Foundation
import Testing
@testable import MindowCore

@Suite("창 레이아웃 저장·복원")
struct LayoutSnapshotTests {
    let orca = "com.stablyso.orca"
    let safari = "com.apple.Safari"
    let laptop = CGRect(x: 0, y: 25, width: 1512, height: 920)
    let monitor = CGRect(x: 1512, y: 0, width: 1920, height: 1055)
    let id = "0193A2C4-7E1F-7B2A-9C3D-1E2F3A4B5C6D"

    func saved(_ title: String, _ index: Int, bundleID: String? = nil) -> LayoutSnapshot.Window {
        LayoutSnapshot.Window(bundleID: bundleID ?? orca, title: title, index: index, display: 0, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    func paired(_ saved: [LayoutSnapshot.Window], _ live: [String]) -> [String: Int] {
        let windows = live.enumerated().map { (window: "\($0.offset):\($0.element)", title: $0.element) }
        return Dictionary(uniqueKeysWithValues: LayoutSnapshot.match(saved, live: windows).map { ($0.live, $0.saved.index) })
    }

    @Test("저장한 화면의 visibleFrame 기준 좌표로 기록하고 같은 화면이면 같은 자리로 돌아간다")
    func 좌표() throws {
        let window = try #require(LayoutSnapshot.Window(
            bundleID: orca, title: "mindow", index: 0, window: CGRect(x: 1612, y: 100, width: 800, height: 600), among: [laptop, monitor]
        ))
        #expect(window.display == 1)
        #expect(window.frame == CGRect(x: 100, y: 100, width: 800, height: 600))
        #expect(window.screen == monitor.size)
        let placement = try #require(window.placement(among: [laptop, monitor]))
        #expect(placement.screen == 1)
        #expect(placement.frame == CGRect(x: 1612, y: 100, width: 800, height: 600))
    }

    @Test("같은 순번 화면의 크기가 다르면 비율로 맞추고, 크기 기록이 없으면 그대로 옮긴다")
    func 비율() throws {
        let window = LayoutSnapshot.Window(
            bundleID: orca, title: "", index: 0, display: 1,
            frame: CGRect(x: 960, y: 0, width: 960, height: 1055), screen: monitor.size
        )
        let smaller = CGRect(x: 1512, y: 0, width: 1280, height: 695)
        let placement = try #require(window.placement(among: [laptop, smaller]))
        #expect(placement.frame == CGRect(x: 2152, y: 0, width: 640, height: 695))
        var handWritten = window
        handWritten.screen = nil
        handWritten.frame = CGRect(x: 10, y: 20, width: 300, height: 200)
        #expect(handWritten.placement(among: [laptop, smaller])?.frame == CGRect(x: 1522, y: 20, width: 300, height: 200))
    }

    @Test("저장한 순번의 화면이 없으면 그 창은 옮기지 않는다")
    func 화면없음() {
        let window = LayoutSnapshot.Window(bundleID: orca, title: "", index: 0, display: 1, frame: .init(x: 0, y: 0, width: 100, height: 100))
        #expect(window.placement(among: [laptop]) == nil)
        #expect(window.placement(among: []) == nil)
    }

    @Test("제목이 같은 창끼리 먼저 짝짓고, 순서가 바뀌어도 제목을 따른다")
    func 제목() {
        let result = paired([saved("README", 0), saved("main.swift", 1)], ["main.swift", "README"])
        #expect(result == ["1:README": 0, "0:main.swift": 1])
    }

    @Test("제목이 안 맞으면 남은 창끼리 순번 순서로 짝짓는다")
    func 순번() {
        let result = paired([saved("Old A", 0), saved("README", 1), saved("Old B", 2)], ["New B", "README", "New C"])
        #expect(result == ["1:README": 1, "0:New B": 0, "2:New C": 2])
    }

    @Test("제목이 같은 창이 여럿이면 차례로 짝짓고 빈 제목은 제목으로 짝짓지 않는다")
    func 중복제목() {
        #expect(paired([saved("Untitled", 0), saved("Untitled", 1)], ["Untitled", "Other", "Untitled"]) == ["0:Untitled": 0, "2:Untitled": 1])
        #expect(paired([saved("", 1), saved("Doc", 0)], ["", "", "Doc"]) == ["2:Doc": 0, "0:": 1])
    }

    @Test("짝이 없는 저장 창·지금 창은 건드리지 않고, 앱이 없으면 아무것도 짝짓지 않는다")
    func 남는창() {
        #expect(paired([saved("A", 0), saved("B", 1), saved("C", 2)], ["X"]) == ["0:X": 0])
        #expect(paired([saved("A", 0)], ["X", "Y"]) == ["0:X": 0])
        #expect(paired([saved("A", 0)], []).isEmpty)
        #expect(paired([], ["X"]).isEmpty)
    }

    @Test("앱 목록은 첫 창이 저장된 순서이고 중복이 없다")
    func 앱목록() {
        let layout = LayoutSnapshot(name: "코딩", windows: [saved("a", 0), saved("b", 0, bundleID: safari), saved("c", 1)])
        #expect(layout.bundleIDs == [orca, safari])
    }

    @Test("저장값을 읽고 그대로 다시 쓴다")
    func 왕복() {
        let stored: [[String: Any]] = [[
            "id": id, "name": "코딩",
            "windows": [
                ["bundleID": orca, "title": "mindow", "index": 0, "display": 0, "frame": [0, 25, 1720, 1415]],
                ["bundleID": safari, "title": "", "index": 1, "display": 1, "frame": [10.5, 0, 800, 600], "screen": [1920, 1055]],
            ],
        ]]
        let layouts = LayoutSnapshots(plist: stored)
        #expect(layouts.layouts == [LayoutSnapshot(id: id, name: "코딩", windows: [
            LayoutSnapshot.Window(bundleID: orca, title: "mindow", index: 0, display: 0, frame: CGRect(x: 0, y: 25, width: 1720, height: 1415)),
            LayoutSnapshot.Window(bundleID: safari, title: "", index: 1, display: 1, frame: CGRect(x: 10.5, y: 0, width: 800, height: 600),
                                  screen: CGSize(width: 1920, height: 1055)),
        ])])
        #expect(LayoutSnapshots(plist: layouts.plist) == layouts)
    }

    @Test("잘못된 창 항목은 그 창만, 잘못된 레이아웃은 그 레이아웃만 건너뛴다")
    func 잘못된값() throws {
        let good: [String: Any] = ["bundleID": orca, "title": "", "index": 0, "display": 0, "frame": [0, 0, 100, 100]]
        let badWindows: [Any] = [
            good.merging(["bundleID": ""]) { $1 },
            good.merging(["title": 3]) { $1 },
            good.merging(["index": -1]) { $1 },
            good.merging(["display": "0"]) { $1 },
            good.merging(["display": true]) { $1 },
            good.merging(["frame": [0, 0, 100]]) { $1 },
            good.merging(["frame": [0, 0, 0, 100]]) { $1 },
            good.merging(["frame": [0, 0, "100", 100]]) { $1 },
            good.merging(["screen": [1920]]) { $1 },
            "window",
            good,
        ]
        let stored: [Any] = [
            ["id": id, "name": "Good", "windows": badWindows],
            ["id": "not-a-uuid", "name": "Bad ID", "windows": []],
            ["id": "0193A2C4-7E1F-7B2A-9C3D-1E2F3A4B5C6E", "name": "   ", "windows": []],
            ["id": "0193A2C4-7E1F-7B2A-9C3D-1E2F3A4B5C6F", "name": "No Windows"],
            ["id": id, "name": "Same ID", "windows": []],
            "layout",
        ]
        let layouts = LayoutSnapshots(plist: stored)
        #expect(layouts.layouts.map(\.name) == ["Good"])
        let window = try #require(layouts.layouts.first?.windows.first)
        #expect(layouts.layouts.first?.windows.count == 1)
        #expect(window.frame == CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(LayoutSnapshots(plist: nil).layouts.isEmpty)
        #expect(LayoutSnapshots(plist: "nonsense").layouts.isEmpty)
    }

    @Test("이름은 대소문자를 가리고 같은 이름이면 첫 레이아웃을 찾는다")
    func 이름찾기() {
        var layouts = LayoutSnapshots()
        layouts.add(LayoutSnapshot(name: "Coding", windows: []))
        let first = layouts.layouts[0].id
        layouts.add(LayoutSnapshot(name: "Coding", windows: [saved("a", 0)]))
        #expect(layouts.first(named: "Coding")?.id == first)
        #expect(layouts.first(named: "coding") == nil)
    }

    @Test("추가·이름 바꾸기는 앞뒤 공백을 지우고 빈 이름은 받지 않으며, 덮어쓰기·삭제는 그 레이아웃만 바꾼다")
    func 편집() {
        var layouts = LayoutSnapshots()
        let added = layouts.add(LayoutSnapshot(id: id, name: "  코딩 ", windows: []))
        let sameID = layouts.add(LayoutSnapshot(id: id, name: "다른 것", windows: []))
        let blank = layouts.add(LayoutSnapshot(name: " ", windows: []))
        #expect(added && !sameID && !blank)
        #expect(layouts.layouts.map(\.name) == ["코딩"])
        layouts.rename(id, to: "  ")
        #expect(layouts.layout(id: id)?.name == "코딩")
        layouts.rename(id, to: " 회의 ")
        #expect(layouts.layout(id: id)?.name == "회의")
        layouts.replaceWindows(of: id, with: [saved("a", 0)])
        #expect(layouts.layout(id: id)?.windows == [saved("a", 0)])
        layouts.remove(id)
        #expect(layouts.layouts.isEmpty)
    }

    @Test("plist에 쓴 뒤 다시 읽어도 같고, 참·거짓 숫자는 순번으로 보지 않는다")
    func 이진plist() throws {
        let layouts = LayoutSnapshots([LayoutSnapshot(id: id, name: "코딩", windows: [
            LayoutSnapshot.Window(bundleID: orca, title: "t", index: 2, display: 1, frame: CGRect(x: -5, y: 0, width: 640.5, height: 480),
                                  screen: CGSize(width: 1280, height: 775)),
        ])])
        let data = try PropertyListSerialization.data(fromPropertyList: layouts.plist, format: .binary, options: 0)
        #expect(LayoutSnapshots(plist: try PropertyListSerialization.propertyList(from: data, format: nil)) == layouts)
        #expect(PlistNumber.index(true) == nil)
        #expect(PlistNumber.real(false) == nil)
    }
}
