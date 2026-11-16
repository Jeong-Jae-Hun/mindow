import CoreGraphics
import Testing
@testable import MindowCore

@Suite("동작 HUD 문구")
struct ActionLabelTests {
    @Test("절반·코너는 순환 단계마다 차지하는 비율을 붙인다")
    func 순환비율() {
        #expect(ActionLabel.text(for: .moveToLeftHalf, step: 0) == "Left Half · 1/2")
        #expect(ActionLabel.text(for: .moveToLeftHalf, step: 1) == "Left Half · 1/3")
        #expect(ActionLabel.text(for: .moveToLeftHalf, step: 2) == "Left Half · 2/3")
        #expect(ActionLabel.text(for: .moveToUpperRight, step: 1) == "Upper Right · 1/3")
    }

    @Test("비율 이름은 순환 비율과 순서·값이 같다")
    func 비율이름() throws {
        #expect(ActionLabel.fractionNames.count == WindowLayout.cycleFractions.count)
        for (name, fraction) in zip(ActionLabel.fractionNames, WindowLayout.cycleFractions) {
            let parts = name.split(separator: "/").compactMap { Double($0) }
            try #require(parts.count == 2)
            #expect(abs(CGFloat(parts[0] / parts[1]) - fraction) < 0.0001)
        }
    }

    @Test("1/3·1/4는 도착한 칸 번호와 칸 수를 붙인다")
    func 칸() {
        #expect(ActionLabel.text(for: .moveToNextThird, step: 1) == "Next Third · 2/3")
        #expect(ActionLabel.text(for: .moveToPreviousFourth, step: 2) == "Previous Fourth · 3/4")
        #expect(ActionLabel.text(for: .moveToNextRowThird, step: 0) == "Next Row Third · 1/3")
    }

    @Test("순환하지 않는 동작은 이름만 쓰고, 범위 밖 단계도 이름만 쓴다")
    func 이름만() {
        #expect(ActionLabel.text(for: .moveToFullscreen, step: 0) == "Fullscreen")
        #expect(ActionLabel.text(for: .splitWithPrevious, step: 0) == "Split with Previous Window")
        #expect(ActionLabel.text(for: .moveToNextDisplay, step: 0) == "Next Display")
        #expect(ActionLabel.text(for: .moveToLeftHalf, step: 5) == "Left Half")
    }
}
