import Foundation

public enum HistoryExportFormat: String, CaseIterable, Sendable {
    case json, csv

    public var fileExtension: String { rawValue }
}

/// The export file formats. Both carry every field Hum stores, with times in
/// ISO 8601 (UTC) and durations in seconds.
enum HistoryExport {
    static let csvHeader = [
        "started_at", "ended_at", "title", "artist", "album", "track_id", "source",
        "context_kind", "context_name", "context_id", "listened_seconds", "duration_seconds",
        "ending", "counts_as_play", "origin",
    ]

    struct Document: Codable {
        var format = "hum-listening-history"
        var version = 1
        var listens: [Row]
    }

    struct Row: Codable {
        var startedAt: String
        var endedAt: String
        var title: String
        var artist: String
        var album: String
        var trackID: String
        var source: String
        var context: Context?
        var listenedSeconds: Double
        var durationSeconds: Double?
        var ending: String
        var countsAsPlay: Bool
        var origin: String

        struct Context: Codable {
            var kind: String
            var name: String?
            var id: String?
        }

        enum CodingKeys: String, CodingKey {
            case startedAt = "started_at", endedAt = "ended_at", title, artist, album
            case trackID = "track_id", source, context
            case listenedSeconds = "listened_seconds", durationSeconds = "duration_seconds"
            case ending, countsAsPlay = "counts_as_play", origin
        }
    }

    static func json(_ listens: [Listen]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Document(listens: listens.map(row)))
    }

    static func csv(_ listens: [Listen]) -> String {
        var lines = [csvHeader.joined(separator: ",")]
        for listen in listens {
            let row = row(listen)
            let fields: [String] = [
                row.startedAt, row.endedAt, row.title, row.artist, row.album, row.trackID, row.source,
                row.context?.kind ?? "", row.context?.name ?? "", row.context?.id ?? "",
                seconds(row.listenedSeconds), row.durationSeconds.map(seconds) ?? "",
                row.ending, row.countsAsPlay ? "true" : "false", row.origin,
            ]
            lines.append(fields.map(quoted).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func row(_ listen: Listen) -> Row {
        Row(
            startedAt: timestamp(listen.startedAt),
            endedAt: timestamp(listen.endedAt),
            title: listen.title,
            artist: listen.artist,
            album: listen.album,
            trackID: listen.trackID.rawValue,
            source: listen.source.rawValue,
            context: listen.context.map { Row.Context(kind: $0.kind.rawValue, name: $0.name, id: $0.identifier) },
            listenedSeconds: (listen.listened * 10).rounded() / 10,
            durationSeconds: listen.duration,
            ending: listen.ending.rawValue,
            countsAsPlay: listen.counts,
            origin: listen.origin.rawValue
        )
    }

    private static func timestamp(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    private static func seconds(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// RFC 4180: quote fields that hold a comma, quote, or line break, doubling quotes.
    static func quoted(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
