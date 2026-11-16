import Foundation
import Testing
@testable import MindowCore

@Suite("mindow:// URL 해석")
struct URLCommandTests {
    func command(_ string: String) -> URLCommand? {
        URL(string: string).flatMap(URLCommand.init)
    }

    @Test("동작 이름은 rawValue로 찾고, 모든 동작이 URL로 닿는다")
    func 동작() {
        #expect(command("mindow://action/MoveToLeftHalf") == .action(.moveToLeftHalf))
        for action in WindowAction.allCases {
            #expect(command("mindow://action/\(action.rawValue)") == .action(action))
        }
    }

    @Test("scheme·host·동작 이름은 대소문자를 가리지 않는다")
    func 대소문자() {
        #expect(command("MINDOW://Action/movetolefthalf") == .action(.moveToLeftHalf))
        #expect(command("mindow://ACTION/MOVETOFULLSCREEN") == .action(.moveToFullscreen))
    }

    @Test("rawValue끼리 대소문자만 다른 것이 없어 대소문자 무시 매칭이 모호하지 않다")
    func 모호하지않음() {
        let lowered = Set(WindowAction.allCases.map { $0.rawValue.lowercased() })
        #expect(lowered.count == WindowAction.allCases.count)
    }

    @Test("이름은 퍼센트 인코딩을 풀고, 레이아웃 이름은 대소문자와 인코딩된 빗금을 그대로 둔다")
    func 레이아웃() {
        #expect(command("mindow://layout/%EC%BD%94%EB%94%A9") == .layout("코딩"))
        #expect(command("mindow://layout/Work%20Setup") == .layout("Work Setup"))
        #expect(command("mindow://layout/Coding") == .layout("Coding"))
        #expect(command("mindow://layout/A%2FB") == .layout("A/B"))
        #expect(command("mindow://action/Move%54oLeftHalf") == .action(.moveToLeftHalf))
    }

    @Test("끝의 빗금 하나는 이름에 영향이 없다")
    func 끝빗금() {
        #expect(command("mindow://action/MoveToLeftHalf/") == .action(.moveToLeftHalf))
    }

    @Test("모르는 동작·host·scheme, 빈 이름, 경로가 둘 이상이면 해석하지 않는다")
    func 거부() {
        #expect(command("mindow://action/MoveToNowhere") == nil)
        #expect(command("mindow://settings/gap") == nil)
        #expect(command("spectacle://action/MoveToLeftHalf") == nil)
        #expect(command("mindow://action") == nil)
        #expect(command("mindow://action/") == nil)
        #expect(command("mindow://layout/") == nil)
        #expect(command("mindow://action/MoveToLeftHalf/extra") == nil)
        #expect(command("mindow:action/MoveToLeftHalf") == nil)
    }

    @Test("쿼리·프래그먼트·사용자·포트가 붙거나 빈 경로 요소가 있으면 해석하지 않는다")
    func 덧붙음거부() {
        #expect(command("mindow://action/MoveToLeftHalf?gap=8") == nil)
        #expect(command("mindow://action/MoveToLeftHalf#x") == nil)
        #expect(command("mindow://user@action/MoveToLeftHalf") == nil)
        #expect(command("mindow://user:pw@action/MoveToLeftHalf") == nil)
        #expect(command("mindow://action:123/MoveToLeftHalf") == nil)
        #expect(command("mindow://action//MoveToLeftHalf") == nil)
        #expect(command("mindow://action/MoveToLeftHalf//") == nil)
    }
}
