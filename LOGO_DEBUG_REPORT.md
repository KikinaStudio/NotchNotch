# Logo Loading Debug Report

## Problem

`loadAppLogo()` returns `nil` at runtime. The logo never appears in the empty chat state or (historically) in the onboarding screen.

---

## The function (AppConstants.swift:34)

```swift
func loadAppLogo() -> NSImage? {
    // Path 1: SPM resource bundle
    if let url = Bundle.module.url(forResource: "logo-white", withExtension: "png"),
       let img = NSImage(contentsOf: url) { return img }
    // Path 2: App bundle Resources/
    if let url = Bundle.main.resourceURL?.appendingPathComponent("logo-white.png"),
       let img = NSImage(contentsOf: url) { return img }
    // Path 3: Relative to executable
    if let execURL = Bundle.main.executableURL?.deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources/logo-white.png"),
       let img = NSImage(contentsOf: execURL) { return img }
    return nil
}
```

---

## What was tried and why it failed

### Fix attempt: Remove `subdirectory: "Resources"`

**Original code:** `Bundle.module.url(forResource: "logo-white", withExtension: "png", subdirectory: "Resources")`

**Hypothesis:** NSBundle already searches inside `<bundle>/Resources/` by default, so `subdirectory: "Resources"` would look for `<bundle>/Resources/Resources/logo-white.png` (double nesting).

**Fix applied:** Removed `subdirectory: "Resources"` parameter.

**Result:** Still doesn't work.

**Why:** The hypothesis about double-nesting was wrong for `.copy()` resources. SPM's `.copy("Resources")` copies the entire source directory as a subdirectory — so the bundle structure might actually need the subdirectory parameter depending on how SPM maps copied directories. More investigation needed (see Bundle Structure section below).

---

## How resources are declared (Package.swift)

```swift
resources: [.copy("Resources")]
```

This uses `.copy()` (not `.process()`). Key difference:
- `.process()` flattens files into the bundle's Resources/ directory
- `.copy()` preserves the directory structure as-is, copying the entire folder

---

## Bundle structure on disk

```
BoaNotch_BoaNotch.bundle/
  Resources/              <-- Bundle's standard Resources dir
    AppIcon.icns
    icon-title.svg
    icon.svg
    logo-white.png        <-- The file IS here
    logo.svg
    menubar-icon.png
    menubar-icon@2x.png
```

The file exists at `BoaNotch_BoaNotch.bundle/Resources/logo-white.png`.

**Open question:** With `.copy("Resources")`, does SPM treat the copied `Resources/` folder as the bundle's own `Resources/` directory (merging), or does it create `Resources/Resources/`? The `ls` output shows only one `Resources/` level, so it appears to merge. But NSBundle's `url(forResource:)` behavior with `.copy()` resources may differ from `.process()` resources — **this needs runtime verification**.

---

## How Bundle.module resolves (resource_bundle_accessor.swift)

SPM auto-generates this accessor:

```swift
extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL
            .appendingPathComponent("BoaNotch_BoaNotch.bundle").path
        let buildPath = "<hardcoded-absolute-path-to-debug-build>/BoaNotch_BoaNotch.bundle"

        let preferredBundle = Bundle(path: mainPath)
        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            Swift.fatalError("could not load resource bundle")
        }
        return bundle
    }()
}
```

### In DEBUG mode (swift build && .build/debug/BoaNotch)

| Step | Path | Exists? |
|------|------|---------|
| `Bundle.main.bundleURL` | `/Library/Developer/CommandLineTools/usr/bin/` (or similar CLI tools path) | - |
| `mainPath` | `<CLT-dir>/BoaNotch_BoaNotch.bundle` | NO |
| `buildPath` (hardcoded) | `.build/arm64-apple-macosx/debug/BoaNotch_BoaNotch.bundle` | YES |
| **Bundle.module resolves to** | **buildPath** | **YES** |

Then `url(forResource: "logo-white", withExtension: "png")` searches this bundle.

**Verdict:** Bundle.module loads successfully. If `url(forResource:)` still returns nil, the issue is how NSBundle searches inside `.copy()`-style bundles.

### In RELEASE APP BUNDLE mode (scripts/run.sh)

| Step | Path | Exists? |
|------|------|---------|
| `Bundle.main.bundleURL` | `.build/notchnotch.app/` | - |
| `mainPath` | `.build/notchnotch.app/BoaNotch_BoaNotch.bundle` | NO (it's in `Contents/Resources/`) |
| `buildPath` (hardcoded) | `.build/arm64-apple-macosx/release/BoaNotch_BoaNotch.bundle` | YES (left over from build) |
| **Bundle.module resolves to** | **buildPath** (same as debug) | **YES** |

**Verdict:** Bundle.module loads from the `.build/` directory leftover, NOT from inside the .app bundle. Fragile but works.

### Path 2: Bundle.main.resourceURL

| Mode | Resolves to | File exists? |
|------|-------------|-------------|
| Debug (CLI executable) | `/Library/Developer/CommandLineTools/usr/bin/` or similar | NO |
| Release (.app bundle) | `.build/notchnotch.app/Contents/Resources/logo-white.png` | YES (run.sh copies it) |

**Verdict:** Only works in release .app bundle mode.

### Path 3: Relative to executable

| Mode | Resolves to | File exists? |
|------|-------------|-------------|
| Debug | `<CLT-dir>/../Resources/logo-white.png` | NO |
| Release | `.build/notchnotch.app/Contents/Resources/logo-white.png` | YES |

**Verdict:** Same as Path 2 — only works in .app bundle mode.

---

## Why ALL paths might fail

### The `.copy()` vs `.process()` theory

With `.copy("Resources")` in Package.swift, SPM copies the directory into the bundle. NSBundle's `url(forResource:withExtension:)` may not find files inside a `.copy()`-ed directory the same way it finds `.process()`-ed resources.

Specifically:
- `.process()` resources are registered in the bundle's resource catalog — `url(forResource:)` finds them by name
- `.copy()` resources are just files on disk — `url(forResource:)` may not index them automatically

**If this is the issue,** the fix would be to either:
1. Change `Package.swift` from `.copy("Resources")` to `.process("Resources")`
2. Or use `Bundle.module.resourceURL` and manually append the path

### The `.process()` fix

```swift
// In Package.swift:
resources: [.process("Resources")]
```

This would flatten all resources into the bundle's root Resources/ directory and register them properly with NSBundle, making `url(forResource:)` work.

**Risk:** `.process()` might rename or restructure files differently. Need to verify.

### The manual path fix

```swift
func loadAppLogo() -> NSImage? {
    // Try Bundle.module's own resource URL
    if let bundleURL = Bundle.module.resourceURL?
        .appendingPathComponent("logo-white.png"),
       let img = NSImage(contentsOf: bundleURL) { return img }
    // ... existing fallbacks ...
}
```

This bypasses `url(forResource:)` entirely and constructs the path manually, which works regardless of `.copy()` vs `.process()`.

---

## Recommended next steps

1. **Quick test:** Add a temporary `print()` in `loadAppLogo()` to see which paths are tried and what `Bundle.module.resourceURL` resolves to at runtime
2. **Try `.process()` instead of `.copy()`** in Package.swift — this is the most likely root cause
3. **Try manual path construction** via `Bundle.module.resourceURL?.appendingPathComponent("logo-white.png")` as a guaranteed fallback
4. **For the .app bundle:** Fix `run.sh` to copy `BoaNotch_BoaNotch.bundle` to the .app root (alongside Contents/) so `mainPath` in the accessor works:
   ```bash
   cp -R .build/release/BoaNotch_BoaNotch.bundle ".build/notchnotch.app/"
   ```

---

## Summary

| Path | Debug CLI | Release .app |
|------|-----------|-------------|
| Path 1: Bundle.module + url(forResource:) | Bundle loads, but url() may return nil due to .copy() | Bundle loads from leftover .build/, same issue |
| Path 2: Bundle.main.resourceURL | Points to CLI tools dir, no file | Works (run.sh copies file) |
| Path 3: Relative to executable | Points to CLI tools dir, no file | Works (same as Path 2) |

**Most likely root cause:** `.copy("Resources")` in Package.swift doesn't register resources with NSBundle's lookup, so `url(forResource:)` returns nil even though the file exists in the bundle directory. Changing to `.process("Resources")` or using manual path construction should fix it.
