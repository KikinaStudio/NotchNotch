#!/usr/bin/env swift
import AppKit
import Foundation

// Validates every SF Symbol used in BoaNotch/Models/SkillIconCatalog.swift
// against the running macOS's symbol set. Exit code 1 if any symbol fails
// to resolve to an NSImage.
//
// Run:  swift scripts/validate_sf_symbols.swift

let here = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let repoRoot = here.deletingLastPathComponent()
let catalogURL = repoRoot.appendingPathComponent("BoaNotch/Models/SkillIconCatalog.swift")

guard let source = try? String(contentsOf: catalogURL, encoding: .utf8) else {
    fputs("Could not read \(catalogURL.path)\n", stderr)
    exit(2)
}

// Match lines of the form:   "category/name": "symbol.name",
// Tolerates trailing inline comments.
let pattern = #""([^"]+)"\s*:\s*"([^"]+)""#
let regex = try NSRegularExpression(pattern: pattern)
let nsSource = source as NSString
let matches = regex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))

var pairs: [(skill: String, symbol: String)] = []
for m in matches where m.numberOfRanges == 3 {
    let key = nsSource.substring(with: m.range(at: 1))
    let val = nsSource.substring(with: m.range(at: 2))
    // Skip the function-signature placeholders or anything that obviously
    // isn't a symbol name (no dots, all-lowercase keys).
    if key.contains("/") || key == "dogfood" || key == "yuanbao" {
        pairs.append((key, val))
    }
}

print("Validating \(pairs.count) SF Symbols on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n")

var invalid: [(String, String)] = []
for (skill, symbol) in pairs {
    if NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil {
        invalid.append((skill, symbol))
        print("  ❌ \(skill) → \(symbol)")
    }
}

if invalid.isEmpty {
    print("\n✅ All \(pairs.count) symbols resolved.")
    exit(0)
} else {
    print("\n❌ \(invalid.count) invalid symbol(s) — fix in BoaNotch/Models/SkillIconCatalog.swift")
    exit(1)
}
