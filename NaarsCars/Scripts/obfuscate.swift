#!/usr/bin/env swift
//
//  obfuscate.swift
//  NaarsCars
//
//  Helper script to obfuscate Supabase credentials for Secrets.swift
//  Usage: swift Scripts/obfuscate.swift "your-url" "your-anon-key"
//

import Foundation

// MARK: - Obfuscation Key (must match Secrets.swift)
let obfuscationKey: [UInt8] = [0x4E, 0x61, 0x61, 0x72, 0x73, 0x43, 0x61, 0x72, 0x73] // "NaarsCars"

// MARK: - Obfuscation Function

func obfuscate(_ input: String) -> [UInt8] {
    let inputBytes = Array(input.utf8)
    var result: [UInt8] = []
    
    for (index, byte) in inputBytes.enumerated() {
        let keyByte = obfuscationKey[index % obfuscationKey.count]
        result.append(byte ^ keyByte)
    }
    
    return result
}

func formatBytes(_ bytes: [UInt8]) -> String {
    return bytes.map { String(format: "0x%02X", $0) }.joined(separator: ", ")
}

// MARK: - Main

guard CommandLine.arguments.count == 3 else {
    print("Usage: swift Scripts/obfuscate.swift \"<supabase-url>\" \"<anon-key>\"")
    print("Example: swift Scripts/obfuscate.swift \"https://xxxxx.supabase.co\" \"eyJhbGc...\"")
    exit(1)
}

let url = CommandLine.arguments[1]
let anonKey = CommandLine.arguments[2]

print("🔐 Obfuscating Supabase credentials...")
print()

let obfuscatedURL = obfuscate(url)
let obfuscatedAnonKey = obfuscate(anonKey)

print("// Obfuscated Supabase URL")
print("private static let obfuscatedURL: [UInt8] = [")
print("    \(formatBytes(obfuscatedURL))")
print("]")
print()
print("// Obfuscated Supabase anon key")
print("private static let obfuscatedAnonKey: [UInt8] = [")
print("    \(formatBytes(obfuscatedAnonKey))")
print("]")
print()
print("✅ Copy the above arrays into Secrets.swift")


