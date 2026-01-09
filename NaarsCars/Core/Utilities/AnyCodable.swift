//
//  AnyCodable.swift
//  NaarsCars
//
//  Utility type for encoding mixed types to JSON for Supabase operations
//

import Foundation

/// A type-erased wrapper for Codable values
/// Used to encode mixed types (String, Int, Bool, Optional, etc.) in dictionaries for Supabase
struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if container.decodeNil() {
            value = Optional<Any>.none as Any
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable value cannot be decoded"
            )
        }
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        // Handle nil/optional values first
        if let optional = value as? (any OptionalProtocol) {
            if optional.isNil {
                try container.encodeNil()
                return
            }
            // Unwrap and recursively encode
            if let unwrapped = optional.unwrapped {
                try AnyCodable(unwrapped).encode(to: encoder)
                return
            }
        }
        
        // Handle concrete types
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let float as Float:
            try container.encode(float)
        case let string as String:
            try container.encode(string)
        default:
            // For other types, try to encode as string
            try container.encode(String(describing: value))
        }
    }
}

// MARK: - Optional Protocol Helper

private protocol OptionalProtocol {
    var isNil: Bool { get }
    var unwrapped: Any? { get }
}

extension Optional: OptionalProtocol {
    var isNil: Bool {
        return self == nil
    }
    
    var unwrapped: Any? {
        switch self {
        case .none:
            return nil
        case .some(let wrapped):
            return wrapped
        }
    }
}

