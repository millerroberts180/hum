import Foundation

extension KeyedDecodingContainer {
    /// Decode `key`, falling back to `defaultValue` when it's missing or malformed.
    ///
    /// Settings use this for every field so a file written by an older or newer Hum,
    /// or edited by hand, loses only the fields it got wrong instead of everything.
    func lenient<Value: Decodable>(_ key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
        (try? decodeIfPresent(Value.self, forKey: key)) ?? defaultValue()
    }
}
