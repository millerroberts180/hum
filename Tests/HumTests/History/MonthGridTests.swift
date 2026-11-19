@testable import HumUI
import Testing

@Suite("Calendar month grid")
struct MonthGridTests {
    @Test func sixMonthsSplitIntoEvenRows() {
        #expect(MonthGrid.columns(count: 6, fitting: 7) == 6)
        #expect(MonthGrid.columns(count: 6, fitting: 6) == 6)
        #expect(MonthGrid.columns(count: 6, fitting: 5) == 3)
        #expect(MonthGrid.columns(count: 6, fitting: 4) == 3)
        #expect(MonthGrid.columns(count: 6, fitting: 2) == 2)
        #expect(MonthGrid.columns(count: 6, fitting: 1) == 1)
    }

    @Test func tooNarrowStillShowsOneColumn() {
        #expect(MonthGrid.columns(count: 6, fitting: 0) == 1)
        #expect(MonthGrid.columns(count: 0, fitting: 3) == 1)
    }
}
