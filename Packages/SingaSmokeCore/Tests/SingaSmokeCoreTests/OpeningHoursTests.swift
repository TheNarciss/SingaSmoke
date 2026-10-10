import Foundation
import XCTest
@testable import SingaSmokeCore

final class OpeningHoursTests: XCTestCase {
    /// October 2026, Singapore time: the 5th is a Monday, the 11th a Sunday.
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.singapore.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func hours(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> OpeningHours {
        guard let parsed = OpeningHours(text) else {
            XCTFail("could not read \"\(text)\"", file: file, line: line)
            return OpeningHours("24/7")!
        }
        return parsed
    }

    func testRoundTheClock() {
        let h = hours("24/7")
        XCTAssertTrue(h.isAlwaysOpen)
        XCTAssertEqual(h.status(at: at(7, 3)), .alwaysOpen)
        XCTAssertEqual(h.schedule.map(\.days), ["Every day"])
        XCTAssertEqual(h.schedule.map(\.hours), ["24 hours"])
        XCTAssertTrue(hours("Mo-Su 00:00-24:00").isAlwaysOpen)
        XCTAssertTrue(hours("PH,Mo-Su 00:00-24:00+").isAlwaysOpen)
        XCTAssertTrue(hours("Mo-Su 00:00-00:00").isAlwaysOpen)
    }

    func testEveryDaySameHours() {
        let h = hours("Mo-Su 07:00-23:00")
        XCTAssertEqual(h.status(at: at(7, 10)), .open(minutesLeft: 13 * 60, closing: 23 * 60))
        XCTAssertEqual(h.status(at: at(7, 6, 30)), .closed(minutesUntil: 30, opening: 7 * 60, daysAhead: 0, weekday: 2))
        XCTAssertEqual(h.status(at: at(7, 23, 30)), .closed(minutesUntil: 450, opening: 7 * 60, daysAhead: 1, weekday: 3))
        XCTAssertEqual(h.schedule.map(\.days), ["Every day"])
        XCTAssertEqual(h.schedule.map(\.hours), ["07:00–23:00"])
        XCTAssertEqual(hours("08:00-23:00").week, hours("Mo-Su 08:00-23:00").week, "no days means every day")
    }

    func testLaterRuleReplacesEarlierDays() {
        let h = hours("Sa-Th 07:30-19:45; Fr 07:30-13:00")
        // Friday 14:00: closed, back on Saturday morning.
        XCTAssertEqual(h.status(at: at(9, 14)), .closed(minutesUntil: 17 * 60 + 30, opening: 7 * 60 + 30, daysAhead: 1, weekday: 5))
        XCTAssertEqual(h.schedule.map(\.days), ["Mon–Thu", "Fri", "Sat–Sun"])
        XCTAssertEqual(h.schedule.map(\.hours), ["07:30–19:45", "07:30–13:00", "07:30–19:45"])
    }

    func testPastMidnight() {
        let h = hours("15:00-02:00")
        // Tuesday 01:00 is still Monday evening's opening.
        XCTAssertEqual(h.status(at: at(6, 1)), .open(minutesLeft: 60, closing: 2 * 60))
        XCTAssertEqual(Format.opening(h.status(at: at(6, 1))), "Open · closes 02:00")
        XCTAssertEqual(Format.opening(h.status(at: at(6, 1, 40))), "Closes soon · 02:00")
        XCTAssertEqual(h.schedule.map(\.hours), ["15:00–02:00"])

        let bar = hours("Tu-Th 17:00-24:00; Fr-Sa 17:00-01:00; Su 12:00-24:00")
        XCTAssertTrue(bar.status(at: at(10, 0, 30)).isOpen, "Saturday 00:30: Friday night")
        XCTAssertEqual(bar.status(at: at(5, 0, 30)),
                       .closed(minutesUntil: 24 * 60 + 16 * 60 + 30, opening: 17 * 60, daysAhead: 1, weekday: 1),
                       "Monday 00:30: Sunday closed at midnight, nothing until Tuesday 17:00")
    }

    func testDayListsAndWrappingRanges() {
        let h = hours("Mo-Th, Su 09:00-17:00")
        XCTAssertEqual(h.week[4], [])
        XCTAssertEqual(h.week[5], [])
        XCTAssertEqual(h.status(at: at(9, 10)), .closed(minutesUntil: 2 * 1440 - 60, opening: 9 * 60, daysAhead: 2, weekday: 6))
        XCTAssertEqual(Format.opening(h.status(at: at(9, 10))), "Closed · opens Sun 09:00")

        let wrap = hours("Fr-We 12:00-21:00")
        XCTAssertEqual(wrap.week.map(\.isEmpty), [false, false, false, true, false, false, false])
        XCTAssertEqual(hours("Mo-Su,PH 06:00-23:00").week, hours("Mo-Su 06:00-23:00").week, "public holidays ignored")
    }

    func testSeveralSpansADay() {
        let h = hours("Mo-Su 06:30-10:30, 12:00-14:30, 18:30-22:30")
        XCTAssertEqual(h.status(at: at(8, 11)), .closed(minutesUntil: 60, opening: 12 * 60, daysAhead: 0, weekday: 3))
        XCTAssertEqual(h.schedule.map(\.hours), ["06:30–10:30, 12:00–14:30, 18:30–22:30"])
    }

    func testLooseWriting() {
        XCTAssertEqual(hours("Sa-Th 10:00-20:00; Fr 16:30 - 20:00").week[4], [OpeningHours.Span(start: 990, end: 1200)])
        XCTAssertEqual(hours("Mo-Sa 05:30:00-17:00").week[0], [OpeningHours.Span(start: 330, end: 1020)])
        XCTAssertEqual(hours("Mo-Fr 09:00-18:00; Sa off").week[5], [])
        XCTAssertEqual(hours("Mo-Fr 09:00-18:00; PH off").week[0], [OpeningHours.Span(start: 540, end: 1080)])
    }

    func testUnreadableValuesAreRejected() {
        XCTAssertNil(OpeningHours("\"varies by stall\""))
        XCTAssertNil(OpeningHours("sunrise-sunset"))
        XCTAssertNil(OpeningHours("Mon-Fri 9am-6pm"))
        XCTAssertNil(OpeningHours(""))
    }

    func testOpenForDaysInARow() {
        // Open round the clock except on Saturday daytime.
        let h = hours("Su-Fr 00:00-00:00; Sa 09:00-23:00")
        XCTAssertFalse(h.isAlwaysOpen)
        XCTAssertEqual(Format.opening(h.status(at: at(11, 10))), "Open 24 hours today")
        XCTAssertEqual(h.status(at: at(10, 8)), .closed(minutesUntil: 60, opening: 9 * 60, daysAhead: 0, weekday: 5))
    }

    func testFormats() {
        XCTAssertEqual(Format.time(0), "00:00")
        XCTAssertEqual(Format.time(1440), "00:00")
        XCTAssertEqual(Format.time(1560), "02:00")
        XCTAssertEqual(Format.time(7 * 60 + 5), "07:05")
        XCTAssertEqual(Format.opening(.open(minutesLeft: 120, closing: 1380)), "Open · closes 23:00")
        XCTAssertEqual(Format.opening(.closed(minutesUntil: 600, opening: 420, daysAhead: 1, weekday: 3)), "Closed · opens tomorrow 07:00")
        XCTAssertEqual(Format.openingShort(.open(minutesLeft: 20, closing: 1380)), "Closes soon")
        XCTAssertEqual(Format.openingShort(.alwaysOpen), "Open 24h")
    }

    func testRetailerKeepsUnreadableTextButNoHours() {
        let shop = Retailer(id: "r", name: "Shop", licensee: nil, address: "1 Road", postalCode: "123456", category: .other,
                            brand: nil, building: nil, validity: nil, coordinate: Fixtures.origin, hoursText: "\"varies\"")
        XCTAssertNil(shop.hours)
        XCTAssertEqual(shop.hoursText, "\"varies\"")
    }
}
