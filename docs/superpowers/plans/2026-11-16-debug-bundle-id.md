# Debug Builds Get Their Own Identity — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Debug builds become a separate app to macOS (`ca.peter-jones.ActivityInspector.dev`, "Activity Inspector Dev", DEV-ribbon icon, own helper label), with Release unchanged.

**Architecture:** Per-configuration build settings on the app target choose the bundle ID, names and icon. One Run Script phase, backed by a checked-in script, writes the helper's launchd plist from `PRODUCT_BUNDLE_IDENTIFIER` and refuses a Release build whose settings have drifted. `HelperConstants` derives every helper name from one pure function of `debug: Bool`, picked by a single `#if DEBUG`.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, Xcode build settings and Run Script phases, zsh, PlistBuddy/plutil, Icon Composer `.icon` bundles.

**Spec:** `docs/superpowers/specs/2026-11-16-debug-bundle-id-design.md`

## Global Constraints

- Release values, unchanged: bundle ID `ca.peter-jones.ActivityInspector`, display name and `CFBundleName` `Activity Inspector`, icon `ActivityInspector`, helper label/Mach service `ca.peter-jones.ActivityInspector.helper`, client requirement with `!entitlement["com.apple.security.get-task-allow"]`.
- Debug values: bundle ID `ca.peter-jones.ActivityInspector.dev`, display name and `CFBundleName` `Activity Inspector Dev`, icon `ActivityInspectorDev`, helper label/Mach service `ca.peter-jones.ActivityInspector.dev.helper`.
- `PRODUCT_NAME` stays `Activity Inspector` in both; the helper's signing identifier stays `ActivityInspectorHelper`; `AppName.display` stays `"Activity Inspector"`.
- **Never edit or `git add` `project.pbxproj`.** Peter makes every project-file change in Xcode from the clicks in Task 2 and commits it himself. The `.xcscheme`, `.icon` folder and `scripts/` are not the pbxproj.
- Nothing Debug-only (plist, icon, `DEBUG` code) may reach a Release build.
- Tests: Swift Testing only; always `-only-testing:ActivityInspectorTests`; Peter quits every copy of the app before a test run (tests end the running app).
- Commit only when Peter says "commit"; never push.

## Review Focus

1. **Stale plist from before the change** — the Debug products folder still holds `ca.peter-jones.ActivityInspector.helper.plist` copied by the old phase; expected: one clean build removes it, and a test fails if `Library/LaunchDaemons` holds anything but the one generated file (Task 2, `exactlyOneLaunchdPlistIsBundled`).
2. **Settings flattened by Xcode's General tab** (FB24809836) — someone edits the bundle ID or display name there and both configurations get the Dev value; expected: a Release build fails with a message naming the setting (Task 2, guard checks run by hand with fake environments).
3. **Build setting and Swift disagree** — bundle ID says `.dev` but `HelperConstants` was compiled without `DEBUG`, or the reverse; expected: a test fails (Task 2, `machServiceIsTheBundleIDPlusHelper`).
4. **Dev icon leaks into Release** — a second `.icon` in the synchronized folder may be compiled into every configuration; expected: a Release build's `Assets.car` and `Contents/Resources` hold no `ActivityInspectorDev` (Task 3 check, with the exclusion setting if it fails).
5. **Incremental build after a configuration switch** — Debug then Release into the same products folder; expected: the Release app holds only the Release plist (the phase always runs, and release.sh archives from a clean `build/release`) (Task 3 check).

---

### Task 1: The Dev icon

**Files:**
- Create: `ActivityInspector/ActivityInspectorDev.icon/` (copy of `ActivityInspector/ActivityInspector.icon/` plus `Assets/4-ribbon.svg`)
- Create: `design/icon/layers/4-ribbon.svg` (same file, kept with the other layers)
- Modify: `design/icon/README.md` (a "Dev icon" section)

**Interfaces:**
- Produces: an app icon named `ActivityInspectorDev` (the `.icon` folder's name), used by Task 2's Debug `ASSETCATALOG_COMPILER_APPICON_NAME`.

- [ ] **Step 1: Make the ribbon layer.** A 1024 × 1024 SVG, no background: a band rotated 45° across the top-right corner — in the tile's own coordinates `<g transform="translate(1024 0) rotate(45)"><rect x="-300" y="160" width="600" height="130" fill="#FFBF33"/> … </g>` — with "DEV" centred on it in near-black (`#0A0A0A`) bold capitals, cap height filling ~70% of the band, letter-spacing ~10 units. "DEV" must be **outlined paths, not `<text>`**: generate them once with a throwaway Swift script in the scratchpad (CoreText `CTFontCreatePathForGlyph` on Helvetica Neue Bold, path elements written out as SVG `d` commands). Icon Composer applies the rounded-square mask, so the band may run past the corner.

- [ ] **Step 2: Assemble the `.icon`.** Copy `ActivityInspector.icon` to `ActivityInspectorDev.icon`, put `4-ribbon.svg` in its `Assets/`, and add a new group **first** in `icon.json`'s `groups` array (first = top-most; today's first group is the lit meters):
```json
{ "layers" : [ { "glass" : false, "image-name" : "4-ribbon.svg", "name" : "4-ribbon" } ],
  "name" : "Ribbon", "shadow" : { "kind" : "none", "opacity" : 0.5 } }
```
Everything else in `icon.json` stays identical to the Release icon.

- [ ] **Step 3: Check it renders.** Render a preview of the ribbon over `design/icon/preview.svg` (e.g. `qlmanage -t -s 1024` on a composite SVG in the scratchpad) and look at it at 1024 and 64 px: "DEV" legible, crisp, not clipped by the corner. Then build (`xcodebuild … build`, the command in CLAUDE.md): expected `** BUILD SUCCEEDED **` (the icon is not selected yet; this proves the folder compiles).

- [ ] **Step 4: Document it** in `design/icon/README.md`: what the Dev icon is (Release icon + "Ribbon" group on top, glass off, no shadow, `#FFBF33` band, outlined "DEV"), why (Debug builds are told apart in the Dock and Login Items; at 32 px only an amber corner shows), and that `layers/4-ribbon.svg` is its source.

- [ ] **Step 5: Commit** (when Peter says "commit"): `ActivityInspector/ActivityInspectorDev.icon`, `design/icon/layers/4-ribbon.svg`, `design/icon/README.md` — "Add the Dev app icon (DEV ribbon)".

---

### Task 2: Debug's identity — names, generated plist, guard

This task is atomic: the Swift names, the project settings and the generated plist must switch together, or the bundled plist and `HelperConstants` disagree and the tests fail.

**Files:**
- Create: `scripts/helper-launchd-plist.sh` (writes the plist; guards Release)
- Create: `Config/AppInfo.plist` (supplies `CFBundleName`; outside the synchronized `ActivityInspector/` folder so it isn't copied as a resource)
- Modify: `ActivityInspector/HelperShared.swift:7-35` (`HelperConstants`)
- Modify: `ActivityInspectorTests/AppNameTests.swift`, `ActivityInspectorTests/PrivilegedHelperTests.swift`
- Delete: `LaunchDaemons/ca.peter-jones.ActivityInspector.helper.plist` (and the `LaunchDaemons/` folder)
- Project settings (Peter, in Xcode — Step 6)

**Interfaces:**
- Consumes: the `ActivityInspectorDev` icon (Task 1).
- Produces, in `HelperConstants` (all `static`, `nonisolated`-safe pure values):
  - `func appBundleID(debug: Bool) -> String` — `"ca.peter-jones.ActivityInspector"` + (`debug ? ".dev" : ""`)
  - `func machServiceName(debug: Bool) -> String` — `appBundleID(debug:) + ".helper"`
  - `func clientRequirement(debug: Bool) -> String` — as today, but `identifier "\(appBundleID(debug:))"`
  - `let isDebugBuild: Bool` — the **only** `#if DEBUG` in `HelperConstants`
  - `let machServiceName: String`, `let plistName: String` (`machServiceName + ".plist"`), `var clientRequirement: String` — current-build values from `isDebugBuild`; existing callers (`PrivilegedHelper.swift`, `ActivityInspectorHelper/main.swift`) keep using these unchanged.
- Produces, in the build: `Contents/Library/LaunchDaemons/<PRODUCT_BUNDLE_IDENTIFIER>.helper.plist`; user-defined build setting `APP_MENU_NAME`.

- [ ] **Step 1: Write the failing tests.**

In `PrivilegedHelperTests.swift`, beside `releaseRefusesDebuggableClients`:
```swift
@Test func eachConfigurationHasItsOwnNames() {
    #expect(HelperConstants.appBundleID(debug: false) == "ca.peter-jones.ActivityInspector")
    #expect(HelperConstants.appBundleID(debug: true) == "ca.peter-jones.ActivityInspector.dev")
    #expect(HelperConstants.machServiceName(debug: false) == "ca.peter-jones.ActivityInspector.helper")
    #expect(HelperConstants.machServiceName(debug: true) == "ca.peter-jones.ActivityInspector.dev.helper")
    #expect(HelperConstants.clientRequirement(debug: false).contains(#"identifier "ca.peter-jones.ActivityInspector" and"#))
    #expect(HelperConstants.clientRequirement(debug: true).contains(#"identifier "ca.peter-jones.ActivityInspector.dev" and"#))
}
```
In `AppNameTests.swift` (the test host is the Debug app):
- `theBuiltAppCarriesThePublicName`: `CFBundleName == "Activity Inspector Dev"`, `CFBundleDisplayName == "Activity Inspector Dev"`, `bundleURL.lastPathComponent == "Activity Inspector.app"` (PRODUCT_NAME unchanged).
- `theBundleIDIsTheDevOne` (renamed): `Bundle.main.bundleIdentifier == "ca.peter-jones.ActivityInspector.dev"` and `HelperConstants.isDebugBuild`.
- `machServiceIsTheBundleIDPlusHelper`: `Bundle.main.bundleIdentifier.map { $0 + ".helper" } == HelperConstants.machServiceName`.
- `theBundledPlistMatchesHelperConstants` (replaces `theBundledHelperCarriesTheNewNames`): helper executable exists as today; reading `Contents/Library/LaunchDaemons/\(HelperConstants.plistName)` as a dictionary gives `Label == machServiceName`, `MachServices` keys `== [machServiceName]`, `BundleProgram == "Contents/MacOS/ActivityInspectorHelper"`, `AssociatedBundleIdentifiers == [Bundle.main.bundleIdentifier!]`.
- `exactlyOneLaunchdPlistIsBundled`: `contentsOfDirectory` of `Contents/Library/LaunchDaemons` `== [HelperConstants.plistName]`.
- `noSourceFileSaysTheOldName`: folders become `["ActivityInspector", "ActivityInspectorHelper", "Config"]`.

- [ ] **Step 2: Run them; expect failures.** Run the unit tests (CLAUDE.md command, teed to a log). Expected: compile errors for the missing `HelperConstants` functions. That is the failing state.

- [ ] **Step 3: Implement `HelperConstants`** to the Interfaces block above. Keep the doc comments' reasoning (why Release refuses debuggable clients); add one line saying the Debug names exist so a Debug build never shares background-item records with the release.

- [ ] **Step 4: Write `scripts/helper-launchd-plist.sh`** (zsh, `set -euo pipefail`, executable). Reads only build-setting environment variables.
  1. **Guard**, only when `CONFIGURATION == Release`: fail (print `error: <setting> is '<value>', expected '<value>'. Fix it in Build Settings, not the General tab (FB24809836). See docs/superpowers/specs/2026-11-16-debug-bundle-id-design.md.` and exit 1) unless `PRODUCT_BUNDLE_IDENTIFIER == ca.peter-jones.ActivityInspector`, `INFOPLIST_KEY_CFBundleDisplayName == "Activity Inspector"`, `APP_MENU_NAME == "Activity Inspector"`, `ASSETCATALOG_COMPILER_APPICON_NAME == ActivityInspector`, and `SWIFT_ACTIVE_COMPILATION_CONDITIONS` has no word `DEBUG`. Check all, report every failure, then exit.
  2. **Write** `$SCRIPT_OUTPUT_FILE_0` (the phase's one declared output) with `plutil -create xml1` then `plutil -insert`: `Label` and a `MachServices` dict, both `"$PRODUCT_BUNDLE_IDENTIFIER.helper"`; `BundleProgram` `Contents/MacOS/ActivityInspectorHelper`; `AssociatedBundleIdentifiers` array with `$PRODUCT_BUNDLE_IDENTIFIER`. `mkdir -p` its folder first.

- [ ] **Step 5: Check the script by hand** before it's wired in, with fake environments in the scratchpad:
  - Debug env (`CONFIGURATION=Debug PRODUCT_BUNDLE_IDENTIFIER=ca.peter-jones.ActivityInspector.dev SCRIPT_OUTPUT_FILE_0=<scratch>/x.plist`): exit 0; `plutil -p` shows Label `ca.peter-jones.ActivityInspector.dev.helper` and the other three keys.
  - Release env with correct values (all five settings): exit 0, Release label.
  - Release env with each setting wrong in turn (5 runs, e.g. bundle ID `…​.dev`, `SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG"`): exit 1 and an `error:` line naming that setting; no plist written.

- [ ] **Step 6: Peter's Xcode changes** (hand him exactly these; wait for "done"). App target **ActivityInspector** ▸ **Build Settings** ▸ **All** + **Levels**, editing per configuration (expand the setting's disclosure triangle; never the General tab):
  1. **Product Bundle Identifier**: Debug `ca.peter-jones.ActivityInspector.dev` (Release unchanged).
  2. **Bundle Display Name** (`INFOPLIST_KEY_CFBundleDisplayName`): Debug `Activity Inspector Dev`, Release `Activity Inspector`.
  3. **+ ▸ Add User-Defined Setting** `APP_MENU_NAME`: Debug `Activity Inspector Dev`, Release `Activity Inspector`.
  4. **Info.plist File** (`INFOPLIST_FILE`), both: `Config/AppInfo.plist` (Generate Info.plist File stays Yes; Xcode merges the two). Create the file first (Claude does): a plist with only `CFBundleName` = `$(APP_MENU_NAME)`.
  5. **Primary App Icon Set Name** (`ASSETCATALOG_COMPILER_APPICON_NAME`): Debug `ActivityInspectorDev`.
  6. **Build Phases**: delete the Copy Files phase whose destination is `Contents/Library/LaunchDaemons` (keep the Executables one with the helper). In the Project navigator, delete the `ca.peter-jones.ActivityInspector.helper.plist` reference (Remove Reference; Claude deletes the file).
  7. **+ ▸ New Run Script Phase**, drag it after the remaining Copy Files phase, name it "Helper launchd plist": shell `/bin/zsh`, script `"$SRCROOT/scripts/helper-launchd-plist.sh"`; Input Files `$(SRCROOT)/scripts/helper-launchd-plist.sh`; Output Files `$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Library/LaunchDaemons/$(PRODUCT_BUNDLE_IDENTIFIER).helper.plist`; **untick** "Based on dependency analysis" (it must run every build so a configuration switch can't leave a stale file).
  Then Claude confirms with `xcodebuild -showBuildSettings -configuration Debug` and `-configuration Release`, grepping the five settings: expected exactly the Global Constraints values.

- [ ] **Step 7: Remove the old plist file** (`LaunchDaemons/…helper.plist`, then the empty folder), and **one clean build** (`xcodebuild … clean build`). Expected: `** BUILD SUCCEEDED **`; `ls "<Debug app>/Contents/Library/LaunchDaemons"` shows only `ca.peter-jones.ActivityInspector.dev.helper.plist`. Tell Peter first: a clean build replaces the helper binary (CLAUDE.md gotcha).

- [ ] **Step 8: Run the unit tests** (Peter has quit every copy). Expected: all pass, including every test from Step 1. Then mutation checks, restoring each after: change the script's Label suffix to `.helpr` → `theBundledPlistMatchesHelperConstants` fails; flip `isDebugBuild`'s `#if` branches → `machServiceIsTheBundleIDPlusHelper` fails.

- [ ] **Step 9: Commit** (when Peter says "commit"), **without the pbxproj** — Peter commits that himself: `scripts/helper-launchd-plist.sh`, `Config/AppInfo.plist`, `ActivityInspector/HelperShared.swift`, both test files, the deleted plist — "Give Debug builds their own bundle ID and helper names".

---

### Task 3: Release stays exactly as it was

**Files:**
- Modify: `scripts/release.sh`
- Modify: `ActivityInspector.xcodeproj/xcshareddata/xcschemes/ActivityInspector.xcscheme:80` (Profile action)

**Interfaces:**
- Consumes: the generated plist path and Release values from Task 2.

- [ ] **Step 1: A plain Release build** into the scratchpad (`xcodebuild … -configuration Release -derivedDataPath <scratch>/rel build`). Expected: `** BUILD SUCCEEDED **`; in the built app, `Library/LaunchDaemons` holds only `ca.peter-jones.ActivityInspector.helper.plist` with Label `ca.peter-jones.ActivityInspector.helper` and AssociatedBundleIdentifiers `[ca.peter-jones.ActivityInspector]`; `CFBundleIdentifier`, `CFBundleName`, `CFBundleDisplayName` are the Release values; `strings` on `Contents/MacOS/ActivityInspectorHelper` and on the app executable finds no `.dev.helper`.

- [ ] **Step 2: Dev icon absent from Release.** `xcrun assetutil --info Contents/Resources/Assets.car | grep -c ActivityInspectorDev` → expected `0`, and no `ActivityInspectorDev*` in `Contents/Resources`. If either is present: Peter adds Release-only `EXCLUDED_SOURCE_FILE_NAMES = ActivityInspectorDev.icon` (Build Settings ▸ Excluded Source File Names, Release row) and Step 1–2 rerun; add the setting to the Task 2 guard's list.

- [ ] **Step 3: Extend `release.sh`.** After "Checking signatures": read `$APP/Contents/Library/LaunchDaemons/ca.peter-jones.ActivityInspector.helper.plist` with PlistBuddy and `fail` unless Label is `ca.peter-jones.ActivityInspector.helper` and `AssociatedBundleIdentifiers:0` is `ca.peter-jones.ActivityInspector`, the folder holds exactly that one file, `CFBundleIdentifier` is `ca.peter-jones.ActivityInspector`, and `strings "$HELPER" "$APP/Contents/MacOS/$APP_NAME" | grep -q '\.dev\.helper'` finds nothing. After the DMG is stapled and validated: `rm -rf "$EXPORT" "$STAGE"` with a comment (loose Release-ID copies that get launched and asked to Install Helper recreate the 2026-11-16 EX_CONFIG failure). Keep the archive (it's the record).
  Verify the new checks without notarizing: run just that block (extracted into a scratch script) against the Step 1 Release app → passes; against the Debug app → fails with the Label message. Running the whole `release.sh` uploads to Apple — only with Peter's go-ahead.

- [ ] **Step 4: Profile builds Debug.** In the scheme file, the `<ProfileAction` `buildConfiguration = "Release"` → `"Debug"`. Expected: `grep -A1 '<ProfileAction' …xcscheme` shows Debug.

- [ ] **Step 5: Commit** (when Peter says "commit"): `scripts/release.sh`, the `.xcscheme` — "Check the release's helper names; profile Debug builds".

---

### Task 4: Docs, TODO, and Peter's hand checks

**Files:**
- Modify: `CLAUDE.md` (helper section; "The test host IS the app"; `defaults` gotcha; Build and test)
- Modify: `TODO.md` (the Debug bundle ID item)
- Modify: `ActivityInspector/BatteryHistory.swift:69` (comment only)

- [ ] **Step 1: CLAUDE.md.** Record: Debug vs Release identity table (short); the plist is generated by `scripts/helper-launchd-plist.sh`, which also guards Release; `LaunchDaemons/` is gone; the Dev helper needs its own approval in Login Items, accepts debuggable clients, and must be unregistered (Privileged Helper… ▸ uninstall) before deleting DerivedData or it is orphaned like the 2026-11-16 failure; both copies run as a process named `Activity Inspector`, so `pgrep -x`/`pkill`/`killall` by name hit both — use `pgrep -fl` and the path; the test host's preferences are now `~/Library/Preferences/ca.peter-jones.ActivityInspector.dev.plist`, not Peter's everyday copy's; update the "A helper registration belongs to the copy…" note to say the planned fix landed.

- [ ] **Step 2: Small fixes.** `BatteryHistory.swift:69` comment: the folder is named after the bundle ID (`ca.peter-jones.ActivityInspector`, or `….dev` for Debug). `TODO.md`: the item's `.debug` → `.dev`, then tick it. Build: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Peter's hand checks** (list them for him; record the answers in the commit message):
  1. The Debug app shows the DEV-ribbon icon in the Dock and "Activity Inspector Dev" as its app-menu title.
  2. Privileged Helper… ▸ Install in the Debug app, approve it in Login Items, then `launchctl print system/ca.peter-jones.ActivityInspector.dev.helper` shows it running, and the release copy's `…ActivityInspector.helper` is still running.
  3. With the release copy open, run the unit tests: the release copy stays open.

- [ ] **Step 4: Commit** (when Peter says "commit"): `CLAUDE.md`, `TODO.md`, `BatteryHistory.swift` — "Record Debug's own identity in CLAUDE.md". Remind Peter to run `npm run review` in `~/Projects/review-harness` for the ticked item.
