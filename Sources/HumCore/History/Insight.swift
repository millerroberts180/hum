import Foundation

/// One observation about a song or a session, with the numbers behind it.
public struct Insight: Identifiable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        // Song
        case firstTime
        case togetherTime
        case firstAndLast
        case pattern
        case relationship
        case rank
        case milestone
        // Session
        case sessionSummary
        case sessionBalance
        case sessionSources
        case sessionReturns
        case sessionLongest

        public var subject: Subject {
            switch self {
            case .firstTime, .togetherTime, .firstAndLast, .pattern, .relationship, .rank, .milestone: .song
            case .sessionSummary, .sessionBalance, .sessionSources, .sessionReturns, .sessionLongest: .session
            }
        }
    }

    public enum Subject: Sendable {
        case song, session
    }

    public var kind: Kind
    /// A short heading: "Time together".
    public var title: String
    /// The stat, set in rounded numerals: "23", "71%", "7th". `nil` when there's
    /// no honest number to show.
    public var value: String?
    /// What the stat counts: "plays of Low Tide Radio · 1 hr 11 min".
    public var label: String
    /// A friend's observation, in sentence case: "Usually played late at night".
    public var sentence: String?
    /// The range and source behind the numbers: "Tracked by Hum since Nov 4."
    public var explanation: String
    /// Secondary facts shown when the card is expanded.
    public var details: [String]
    public var timeline: MiniTimelineData?
    /// Higher is more worth showing. Between 0 and 1.
    public var relevance: Double

    public var id: Kind { kind }
    public var subject: Subject { kind.subject }

    public init(
        kind: Kind,
        title: String,
        value: String?,
        label: String,
        sentence: String? = nil,
        explanation: String,
        details: [String] = [],
        timeline: MiniTimelineData? = nil,
        relevance: Double
    ) {
        self.kind = kind
        self.title = title
        self.value = value
        self.label = label
        self.sentence = sentence
        self.explanation = explanation
        self.details = details
        self.timeline = timeline
        self.relevance = relevance
    }

    /// Everything a listener needs, in reading order, for VoiceOver.
    public var spokenSummary: String {
        [title, [value, label].compactMap { $0 }.joined(separator: " "), sentence]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }
}

/// Dots on a hairline from the start of tracking to now: when a song was heard.
public struct MiniTimelineData: Hashable, Sendable {
    public var start: Date
    public var end: Date
    /// Each play's position on the line, from 0 (start) to 1 (now).
    public var marks: [Double]
    public var startLabel: String
    public var endLabel: String

    public init(start: Date, end: Date, marks: [Double], startLabel: String, endLabel: String) {
        self.start = start
        self.end = end
        self.marks = marks
        self.startLabel = startLabel
        self.endLabel = endLabel
    }

    public init(plays: [Date], from start: Date, to end: Date, format: HistoryFormat) {
        let span = max(1, end.timeIntervalSince(start))
        self.init(
            start: start,
            end: end,
            marks: plays.map { min(1, max(0, $0.timeIntervalSince(start) / span)) },
            startLabel: format.day(start, now: end),
            endLabel: "Now"
        )
    }
}
