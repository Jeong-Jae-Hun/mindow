import Testing
@testable import MindowCore

@Suite("단축키 중복")
struct ShortcutConflictsTests {
    let left = KeyBinding(carbonKeyCode: 123, carbonModifiers: 2304)
    let right = KeyBinding(carbonKeyCode: 124, carbonModifiers: 2304)
    let pause = KeyBinding(carbonKeyCode: 35, carbonModifiers: 6400)

    @Test("서로 다른 단축키만 있으면 중복이 없다")
    func 중복없음() {
        let bindings: [String: KeyBinding?] = ["MoveToLeftHalf": left, "MoveToRightHalf": right, "TogglePause": pause]
        #expect(ShortcutConflicts.find(in: bindings).isEmpty)
    }

    @Test("같은 단축키를 가진 이름은 양쪽 모두 서로를 가리킨다")
    func 둘중복() {
        let bindings: [String: KeyBinding?] = ["MoveToLeftHalf": left, "TogglePause": left, "MoveToRightHalf": right]
        #expect(ShortcutConflicts.find(in: bindings) == [
            "MoveToLeftHalf": ["TogglePause"],
            "TogglePause": ["MoveToLeftHalf"],
        ])
    }

    @Test("셋이 겹치면 각자 나머지 둘을, 다른 묶음은 따로 가리킨다")
    func 여러묶음() {
        let bindings: [String: KeyBinding?] = ["A": left, "B": left, "C": left, "D": right, "E": right]
        let conflicts = ShortcutConflicts.find(in: bindings)
        #expect(conflicts["A"] == ["B", "C"])
        #expect(conflicts["C"] == ["A", "B"])
        #expect(conflicts["D"] == ["E"])
        #expect(conflicts["E"] == ["D"])
    }

    @Test("단축키가 없는 이름끼리는 중복이 아니다")
    func 없음은중복아님() {
        let bindings: [String: KeyBinding?] = ["MoveToNextFourth": nil, "MaximizeHeight": nil, "MoveToLeftHalf": left]
        #expect(ShortcutConflicts.find(in: bindings).isEmpty)
    }

    @Test("키가 같아도 수정키가 다르면 중복이 아니다")
    func 수정키다름() {
        let bindings: [String: KeyBinding?] = ["A": left, "B": KeyBinding(carbonKeyCode: 123, carbonModifiers: 6400)]
        #expect(ShortcutConflicts.find(in: bindings).isEmpty)
    }
}
