import Foundation

/// A finished action whose result can't be seen, shown briefly in the HUD.
public struct LibraryNotice: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Added to Favorites.
        case saved
        /// Removed from Favorites.
        case unsaved
    }

    public let id: UUID
    public var kind: Kind
    /// The source the action was for.
    public var source: SourceID?

    public init(_ kind: Kind, source: SourceID?, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
        self.source = source
    }
}

/// An action that didn't work, shown as an inline banner until dismissed.
public struct LibraryFailure: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var message: String
    /// The fix, when there is one, such as opening the source's app.
    public var fix: LibraryUnavailable.Fix?
    /// Whether Try Again repeats the request that failed. Only a failure that
    /// may pass offers it.
    public var canRetry: Bool

    public init(message: String, fix: LibraryUnavailable.Fix? = nil, canRetry: Bool = false, id: UUID = UUID()) {
        self.id = id
        self.message = message
        self.fix = fix
        self.canRetry = canRetry
    }
}
