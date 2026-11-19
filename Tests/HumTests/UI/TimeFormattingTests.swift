import HumCore
@testable import HumUI
import Testing

@Suite("Time formatting")
struct TimeFormattingTests {
    @Test func clockShowsHoursOnlyWhenNeeded() {
        #expect(TimeFormatting.clock(187) == "3:07")
        #expect(TimeFormatting.clock(3765) == "1:02:45")
        #expect(TimeFormatting.clock(59.9) == "0:59")
        #expect(TimeFormatting.clock(-5) == "0:00")
    }

    @Test func remainingUsesATrueMinusSign() {
        #expect(TimeFormatting.remaining(83) == "\u{2212}1:23")
    }

    @Test func seekLabelsFollowTheTrailingTimeSetting() {
        #expect(TimeFormatting.elapsed(62, duration: 220) == "1:02")
        #expect(TimeFormatting.trailing(62, duration: 220, showing: .remaining) == "\u{2212}2:38")
        #expect(TimeFormatting.trailing(62, duration: 220, showing: .total) == "3:40")
        // Past the end (a late position report), remaining stops at zero.
        #expect(TimeFormatting.trailing(230, duration: 220, showing: .remaining) == "\u{2212}0:00")
    }

    /// A song still loading, or a stream, has no length to show.
    @Test func anUnknownLengthShowsDashesRatherThanZero() {
        #expect(TimeFormatting.elapsed(12, duration: 0) == "--:--")
        #expect(TimeFormatting.trailing(12, duration: 0, showing: .remaining) == "--:--")
        #expect(TimeFormatting.trailing(12, duration: 0, showing: .total) == "--:--")
    }

    @Test func spokenTimesReadAsOnePhrase() {
        #expect(TimeFormatting.spoken(62) == "1 minute 2 seconds")
        #expect(TimeFormatting.spoken(0) == "0 seconds")
        #expect(TimeFormatting.spoken(3600) == "1 hour")
        #expect(TimeFormatting.spoken(7322) == "2 hours 2 minutes 2 seconds")
        #expect(TimeFormatting.spokenPosition(62, of: 220) == "1 minute 2 seconds of 3 minutes 40 seconds")
        // A length that isn't known yet isn't read as "of 0 seconds".
        #expect(TimeFormatting.spokenPosition(62, of: 0) == "1 minute 2 seconds")
    }

    @Test func repeatModesHaveSpokenNames() {
        // Read after the label: "Repeat, one song".
        #expect(RepeatButton.spoken(.off) == "off")
        #expect(RepeatButton.spoken(.all) == "all")
        #expect(RepeatButton.spoken(.one) == "one song")
        #expect(RepeatButton.title(.one) == "One Song")
    }

    @Test func volumeReadsAsAWholePercent() {
        // Read after "Volume, slider": "40 percent".
        #expect(VolumeControl.spoken(0.4) == "40 percent")
        #expect(VolumeControl.spoken(0) == "0 percent")
        #expect(VolumeControl.spoken(1) == "100 percent")
        #expect(VolumeControl.spoken(0.996) == "100 percent")
        #expect(VolumeControl.spoken(0.333) == "33 percent")
    }
}
