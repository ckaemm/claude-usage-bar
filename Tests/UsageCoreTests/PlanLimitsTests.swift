import Foundation
import Testing
@testable import UsageCore

@Suite struct PlanLimitsTests {
    @Test func parsesKnownWindowsInOrder() throws {
        let json = #"""
        {"seven_day":{"utilization":12.0,"resets_at":"2026-11-02T08:00:00.000Z"},
         "five_hour":{"utilization":42.5,"resets_at":"2026-10-27T22:00:00Z"},
         "seven_day_opus":null,
         "extra_usage":{"is_enabled":false}}
        """#
        let l = try #require(PlanLimits.parse(Data(json.utf8)))
        #expect(l.windows.map(\.id) == ["five_hour", "seven_day"])
        #expect(l.fiveHour?.utilization == 42.5)
        #expect(l.fiveHour?.resetsAt == LogParser().parseDate("2026-10-27T22:00:00Z"))
        #expect(l.windows[1].resetsAt != nil)
    }

    @Test func unknownShapeReturnsNil() {
        #expect(PlanLimits.parse(Data(#"{"error":{"type":"x"}}"#.utf8)) == nil)
        #expect(PlanLimits.parse(Data("not json".utf8)) == nil)
    }
}
