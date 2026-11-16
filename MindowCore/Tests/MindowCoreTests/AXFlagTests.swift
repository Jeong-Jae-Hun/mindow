import ApplicationServices
import Testing
@testable import MindowCore

@Suite("창 속성 읽기")
struct AXFlagTests {
    @Test("읽은 값이 참·거짓이면 그대로 쓴다")
    func 성공() {
        #expect(AXFlag.value(.success, kCFBooleanTrue) == true)
        #expect(AXFlag.value(.success, kCFBooleanFalse) == false)
    }

    @Test("속성이 없거나 값이 비었거나 Bool이 아니면 거짓으로 본다")
    func 속성없음() {
        #expect(AXFlag.value(.attributeUnsupported, nil) == false)
        #expect(AXFlag.value(.noValue, nil) == false)
        #expect(AXFlag.value(.success, nil) == false)
        #expect(AXFlag.value(.success, "yes" as CFString) == false)
    }

    @Test("앱이 답하지 않았거나 창이 사라졌으면 실패다")
    func 실패() {
        #expect(AXFlag.value(.cannotComplete, nil) == nil)
        #expect(AXFlag.value(.invalidUIElement, nil) == nil)
        #expect(AXFlag.value(.failure, nil) == nil)
        #expect(AXFlag.value(.apiDisabled, nil) == nil)
    }
}
