import AppKit
import HumCore
@testable import HumUI
import SwiftUI
import Testing

/// The Listening History window opens with its sidebar collapsed, for more
/// room (DESIGN.md §6.5, §13.31).
@Suite("Listening History window")
struct HistoryWindowTests {
    @Test func itOpensWithTheSidebarCollapsed() {
        #expect(HistoryWindowPresenter.initialColumnVisibility == .detailOnly)
        #expect(HistoryWindowPresenter.initialColumnVisibility != .automatic)
    }
}

/// The filters and Top's period (DESIGN.md §5.9, family 10).
@MainActor
@Suite("Pill menus")
struct PillMenuTests {
    static let artists: [PillMenu<String>.Option] = [
        .init(value: "Low", title: "Low"),
        .init(value: "Mitski", title: "Mitski"),
    ]

    func artistMenu(_ selection: String) -> PillMenu<String> {
        PillMenu(title: "Artist", selection: .constant(selection), any: .init(value: "", title: "Any Artist"), options: Self.artists)
    }

    @Test func itShowsTheChoice() {
        #expect(artistMenu("").choice == "Any Artist")
        #expect(artistMenu("Mitski").choice == "Mitski")
    }

    /// A filter for an artist whose listens were all removed reads as Any.
    @Test func aChoiceNoLongerOfferedShowsAny() {
        #expect(artistMenu("Gone").choice == "Any Artist")
        let period = PillMenu(title: "Period", selection: .constant("Gone"), options: Self.artists)
        #expect(period.choice == "Low")
    }

    @Test func onlyAFilterOffItsAnyChoiceIsSet() {
        #expect(!artistMenu("").isActive)
        #expect(artistMenu("Low").isActive)
        // Top's period has no Any, so it never reads as a set filter.
        #expect(!PillMenu(title: "Period", selection: .constant("Mitski"), options: Self.artists).isActive)
    }

    @Test func atRestItIsFamilyNine() {
        for hovered in [false, true] {
            let look = PillMenuButtonStyle.look(isPressed: false, isHovered: hovered, isActive: false, isEnabled: true)
            #expect(look == ActionButtonLook.resolve(isPressed: false, isHovered: hovered, isSelected: false, isEnabled: true))
        }
    }

    @Test func aSetFilterLightsItsEdge() {
        let look = PillMenuButtonStyle.look(isPressed: false, isHovered: false, isActive: true, isEnabled: true)
        #expect(look.edge == .accent)
        #expect(look.edgeOpacity == 0.45)
        #expect(look.fill == ActionButtonLook.rest.fill)
        #expect(look.fillOpacity == ActionButtonLook.rest.fillOpacity)
        #expect(PillMenuButtonStyle.titleColor(isActive: true, isEnabled: true) == .accentColor)
        #expect(PillMenuButtonStyle.titleColor(isActive: false, isEnabled: true) == ActionButtonLook.titleColor(isEnabled: true, isDestructive: false))
        #expect(PillMenuButtonStyle.titleColor(isActive: true, isEnabled: false) == ActionButtonLook.titleColor(isEnabled: false, isDestructive: false))
    }

    @Test func pressingShowsFamilyNinesPress() {
        let press = ActionButtonLook.resolve(isPressed: true, isHovered: true, isSelected: false, isEnabled: true)
        #expect(PillMenuButtonStyle.look(isPressed: true, isHovered: true, isActive: true, isEnabled: true) == press)
        #expect(PillMenuButtonStyle.look(isPressed: true, isHovered: true, isActive: false, isEnabled: true) == press)
        let reduced = PillMenuButtonStyle.look(isPressed: true, isHovered: true, isActive: false, isEnabled: true, reduceMotion: true)
        #expect(reduced.scale == 1)
    }

    func render(_ menu: PillMenu<String>) throws -> (size: CGSize, pixels: [UInt8]) {
        let view = NSHostingView(rootView: menu.padding(8).background(Color.white))
        view.appearance = NSAppearance(named: .aqua)
        view.setFrameSize(view.fittingSize)
        view.layoutSubtreeIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try #require(rep.bitmapData)
        return (view.bounds.size, Array(UnsafeBufferPointer(start: data, count: rep.bytesPerRow * rep.pixelsHigh)))
    }

    /// The capsule draws (a menu's own button would be shorter), and a set
    /// filter draws differently from the same choice with no Any to set it
    /// apart from.
    @Test func itDrawsTheCapsuleAndASetFilter() throws {
        let plain = try render(PillMenu(title: "Artist", selection: .constant("Low"), options: Self.artists))
        let set = try render(artistMenu("Low"))
        #expect(plain.size.height >= ActionButtonMetrics.minHeight + 16)
        #expect(plain.size == set.size)
        #expect(plain.pixels.contains { $0 < 200 }, "the title and the edge show on white")
        #expect(plain.pixels != set.pixels)
    }
}

/// The calendar's arrow keys (DESIGN.md §5.7): a day either way, a week up
/// or down, never past either end.
@Suite("Calendar keys")
struct HeatCalendarKeyTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    static func day(_ number: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: number))!
    }

    static let start = day(1)
    /// Afternoon, as a real "today" is.
    static let today = day(20).addingTimeInterval(15 * 3600)

    static func move(_ selection: Date?, _ key: KeyEquivalent) -> Date? {
        HeatCalendar.day(moving: selection, by: HeatCalendar.offset(for: key), from: start, through: today, calendar: calendar)
    }

    @Test func theArrowsStepADayOrAWeek() {
        #expect(HeatCalendar.offset(for: .leftArrow) == -1)
        #expect(HeatCalendar.offset(for: .rightArrow) == 1)
        #expect(HeatCalendar.offset(for: .upArrow) == -7)
        #expect(HeatCalendar.offset(for: .downArrow) == 7)
        #expect(Self.move(Self.day(10), .leftArrow) == Self.day(9))
        #expect(Self.move(Self.day(10), .rightArrow) == Self.day(11))
        #expect(Self.move(Self.day(10), .upArrow) == Self.day(3))
        #expect(Self.move(Self.day(10), .downArrow) == Self.day(17))
    }

    @Test func theFirstPressPicksToday() {
        for key: KeyEquivalent in [.leftArrow, .rightArrow, .upArrow, .downArrow] {
            #expect(Self.move(nil, key) == Self.day(20))
        }
    }

    @Test func theSelectionStaysAtEitherEnd() {
        #expect(Self.move(Self.day(20), .rightArrow) == nil)
        #expect(Self.move(Self.day(15), .downArrow) == nil)
        #expect(Self.move(Self.day(1), .leftArrow) == nil)
        #expect(Self.move(Self.day(5), .upArrow) == nil)
        #expect(Self.move(Self.day(13), .downArrow) == Self.day(20))
        #expect(Self.move(Self.day(8), .upArrow) == Self.day(1))
    }
}
