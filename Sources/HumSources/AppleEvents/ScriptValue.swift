import CoreServices
import Foundation
import HumCore

/// A Sendable copy of an Apple Event reply, so results can leave the Apple Events
/// queue without carrying `NSAppleEventDescriptor` along.
public enum ScriptValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case data(Data)
    case list([ScriptValue])
    /// Keyed by the four-character code of each property.
    case record([String: ScriptValue])

    public var string: String? {
        switch self {
        case .string(let value): value
        case .int(let value): String(value)
        case .double(let value): String(value)
        default: nil
        }
    }

    public var double: Double? {
        switch self {
        case .double(let value): value
        case .int(let value): Double(value)
        case .string(let value): Double(value)
        default: nil
        }
    }

    public var int: Int? {
        switch self {
        case .int(let value): value
        case .double(let value) where value.isFinite: Int(value)
        case .string(let value): Int(value)
        default: nil
        }
    }

    public var bool: Bool? {
        switch self {
        case .bool(let value): value
        case .int(let value): value != 0
        case .string(let value): ["true", "yes"].contains(value.lowercased()) ? true : (["false", "no"].contains(value.lowercased()) ? false : nil)
        default: nil
        }
    }

    public var list: [ScriptValue]? {
        if case .list(let values) = self { return values }
        return nil
    }

    public var data: Data? {
        if case .data(let value) = self { return value }
        return nil
    }

    /// `nil` for `.null`, otherwise `self`. Lets parsers treat AppleScript's
    /// `missing value` like an absent field.
    public var nonNull: ScriptValue? {
        self == .null ? nil : self
    }
}

extension ScriptValue {
    /// Image and raw-data descriptor types, returned as bytes rather than coerced.
    private static let dataTypes: Set<DescType> = [
        fourCharCode("tdta"), fourCharCode("rdat"), fourCharCode("JPEG"), fourCharCode("PNGf"),
        fourCharCode("TIFF"), fourCharCode("GIFf"), fourCharCode("BMP "), fourCharCode("PICT"),
    ]

    init(_ descriptor: NSAppleEventDescriptor) {
        switch descriptor.descriptorType {
        case DescType(typeNull):
            self = .null
        case DescType(typeType) where descriptor.typeCodeValue == Self.fourCharCode("msng"):
            self = .null
        case DescType(typeTrue):
            self = .bool(true)
        case DescType(typeFalse):
            self = .bool(false)
        case DescType(typeBoolean):
            self = .bool(descriptor.booleanValue)
        case DescType(typeSInt16), DescType(typeSInt32), DescType(typeUInt16):
            self = .int(Int(descriptor.int32Value))
        case DescType(typeSInt64), DescType(typeUInt32), DescType(typeUInt64):
            self = .int(Self.integer(from: descriptor.data, type: descriptor.descriptorType))
        case DescType(typeIEEE64BitFloatingPoint), DescType(typeIEEE32BitFloatingPoint):
            self = .double(descriptor.doubleValue)
        case DescType(typeUnicodeText), DescType(typeUTF8Text), DescType(typeChar):
            self = .string(descriptor.stringValue ?? "")
        case DescType(typeAEList):
            let count = descriptor.numberOfItems
            self = .list(count > 0 ? (1...count).compactMap { descriptor.atIndex($0).map(ScriptValue.init) } : [])
        case DescType(typeAERecord):
            var fields: [String: ScriptValue] = [:]
            let count = descriptor.numberOfItems
            if count > 0 {
                for index in 1...count {
                    let keyword = descriptor.keywordForDescriptor(at: index)
                    if let value = descriptor.atIndex(index) {
                        fields[Self.string(fromFourCharCode: keyword)] = ScriptValue(value)
                    }
                }
            }
            self = .record(fields)
        case let type where Self.dataTypes.contains(type):
            self = .data(descriptor.data)
        default:
            if let string = descriptor.stringValue {
                self = .string(string)
            } else {
                self = .data(descriptor.data)
            }
        }
    }

    private static func integer(from data: Data, type: DescType) -> Int {
        switch type {
        case DescType(typeUInt32) where data.count >= 4:
            return Int(data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        case DescType(typeSInt64) where data.count >= 8:
            return Int(data.withUnsafeBytes { $0.loadUnaligned(as: Int64.self) })
        case DescType(typeUInt64) where data.count >= 8:
            return Int(truncatingIfNeeded: data.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) })
        default:
            return 0
        }
    }

    static func fourCharCode(_ string: String) -> FourCharCode {
        string.utf8.prefix(4).reduce(0) { ($0 << 8) | FourCharCode($1) }
    }

    static func string(fromFourCharCode code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
