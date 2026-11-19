import Foundation

extension AppDirectories {
    /// The listening-history database. Demo mode keeps its own file so demo
    /// listening never mixes with real history.
    public func historyDatabase(demo: Bool) -> URL {
        applicationSupport.appendingPathComponent(demo ? "History-Demo.sqlite" : "History.sqlite")
    }
}
