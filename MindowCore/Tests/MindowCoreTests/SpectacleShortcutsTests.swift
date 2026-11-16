import Foundation
import Testing
@testable import MindowCore

@Suite("Spectacle 단축키 가져오기")
struct SpectacleShortcutsTests {
    @Test("실제 Shortcuts.json의 18개 항목이 모두 같은 키로 들어온다")
    func 실물가져오기() throws {
        let url = try #require(Bundle.module.url(forResource: "Shortcuts", withExtension: "json", subdirectory: "Fixtures"))
        let result = try SpectacleShortcuts.parse(Data(contentsOf: url))
        #expect(result.skipped.isEmpty)
        #expect(result.bindings.count == 18)
        #expect(result.bindings == SpectacleShortcuts.defaults)
    }

    @Test("수식키와 키 이름을 Carbon 값으로 바꾼다")
    func 키변환() {
        #expect(KeyBinding(spectacle: "alt+cmd+left") == KeyBinding(carbonKeyCode: 123, carbonModifiers: 2304))
        #expect(KeyBinding(spectacle: "ctrl+alt+right") == KeyBinding(carbonKeyCode: 124, carbonModifiers: 6144))
        #expect(KeyBinding(spectacle: "alt+shift+cmd+z") == KeyBinding(carbonKeyCode: 6, carbonModifiers: 2816))
    }

    @Test("모르는 키·수식키는 변환하지 않는다")
    func 모르는키() {
        #expect(KeyBinding(spectacle: "hyper+left") == nil)
        #expect(KeyBinding(spectacle: "cmd+numpad5") == nil)
        #expect(KeyBinding(spectacle: "") == nil)
    }

    @Test("모르는 동작·비어 있는 키는 건너뛴 목록에 남긴다")
    func 건너뛰기() throws {
        let json = """
        [{"shortcut_name":"MoveToCenter","shortcut_key_binding":"alt+cmd+c"},
         {"shortcut_name":"MoveToFrontWindow","shortcut_key_binding":"alt+cmd+w"},
         {"shortcut_name":"MoveToFullscreen","shortcut_key_binding":null}]
        """
        let result = try SpectacleShortcuts.parse(Data(json.utf8))
        #expect(result.bindings == [.moveToCenter: KeyBinding(carbonKeyCode: 8, carbonModifiers: 2304)])
        #expect(result.skipped == ["MoveToFrontWindow: alt+cmd+w", "MoveToFullscreen: none"])
    }

    @Test("JSON이 아니면 오류를 던진다")
    func 깨진파일() {
        #expect(throws: (any Error).self) { try SpectacleShortcuts.parse(Data("nope".utf8)) }
    }
}
