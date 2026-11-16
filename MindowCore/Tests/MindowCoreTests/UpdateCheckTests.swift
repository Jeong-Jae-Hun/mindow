import Foundation
import Testing
@testable import MindowCore

@Suite("업데이트 확인")
struct UpdateCheckTests {
    func release(tag: String, url: String = "https://github.com/Jeong-Jae-Hun/mindow/releases/tag/v0.2.0",
                 draft: Bool = false, prerelease: Bool = false) -> Data {
        Data("""
        {"tag_name":"\(tag)","html_url":"\(url)","draft":\(draft),"prerelease":\(prerelease),
         "name":"Mindow \(tag)","assets":[{"name":"Mindow.zip"}],"author":{"login":"x"}}
        """.utf8)
    }

    @Test("버전은 숫자별로 비교해 0.10.0이 0.9.1보다 크고, 앞의 v는 무시한다")
    func 숫자별비교() throws {
        let tenth = try #require(ReleaseVersion("0.10.0"))
        let ninth = try #require(ReleaseVersion("0.9.1"))
        #expect(tenth > ninth)
        #expect(ReleaseVersion("v0.2.0") == ReleaseVersion("0.2.0"))
        #expect(ReleaseVersion("0.2") == ReleaseVersion("0.2.0"))
        #expect(ReleaseVersion("v1.0.0")?.description == "1.0.0")
    }

    @Test("숫자가 아닌 버전·접미사 붙은 버전은 읽지 않는다")
    func 이상한버전() {
        for string in ["", "v", "vv0.2.0", "0..2", "0.2.", "1.x", "+1.0", " 0.2.0", "0.2.0-beta", "0.2.0 ", "١.٢"] {
            #expect(ReleaseVersion(string) == nil, "\(string)")
        }
    }

    @Test("최신 릴리스 JSON에서 태그와 페이지만 읽고 다른 필드는 무시한다")
    func 응답해석() throws {
        let latest = try #require(LatestRelease(json: release(tag: "v0.2.0")))
        #expect(latest.version == ReleaseVersion("0.2.0"))
        #expect(latest.url.absoluteString == "https://github.com/Jeong-Jae-Hun/mindow/releases/tag/v0.2.0")
    }

    @Test("지금 버전보다 클 때만 새 버전이고, 같거나 작거나 지금 버전을 모르면 아니다")
    func 새버전판정() throws {
        let latest = try #require(LatestRelease(json: release(tag: "v0.10.0")))
        #expect(latest.isNewer(than: "0.9.1"))
        #expect(!latest.isNewer(than: "0.10.0"))
        #expect(!latest.isNewer(than: "0.11"))
        #expect(!latest.isNewer(than: ""))
    }

    @Test("접미사 붙은 태그는 같은 번호의 정식 버전보다 새것으로 보지 않는다")
    func 접미사태그() {
        #expect(LatestRelease(json: release(tag: "v0.2.0-beta")) == nil)
    }

    @Test("초안·프리릴리스·github.com 밖 페이지는 무시한다")
    func 무시할릴리스() {
        #expect(LatestRelease(json: release(tag: "v0.2.0", draft: true)) == nil)
        #expect(LatestRelease(json: release(tag: "v0.2.0", prerelease: true)) == nil)
        #expect(LatestRelease(json: release(tag: "v0.2.0", url: "http://github.com/x")) == nil)
        #expect(LatestRelease(json: release(tag: "v0.2.0", url: "https://example.com/x")) == nil)
    }

    @Test("깨진 JSON·필드 없는 응답·rate limit 응답은 무시한다")
    func 깨진응답() {
        #expect(LatestRelease(json: Data("nope".utf8)) == nil)
        #expect(LatestRelease(json: Data()) == nil)
        #expect(LatestRelease(json: Data(#"{"tag_name":"v0.2.0"}"#.utf8)) == nil)
        #expect(LatestRelease(json: Data(#"{"tag_name":2,"html_url":"https://github.com/x"}"#.utf8)) == nil)
        #expect(LatestRelease(json: Data(#"{"message":"API rate limit exceeded","documentation_url":"https://docs.github.com"}"#.utf8)) == nil)
    }

    @Test("한 번도 안 했거나 24시간이 지났거나 기록이 미래면 확인할 때다")
    func 확인주기() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(UpdateSchedule.isDue(lastCheck: nil, now: now))
        #expect(UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(-UpdateSchedule.interval), now: now))
        #expect(!UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(-UpdateSchedule.interval + 60), now: now))
        #expect(UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(60), now: now))
    }
}
