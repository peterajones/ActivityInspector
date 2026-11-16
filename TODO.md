# TODO

_Single source of truth for unfinished work in this project. Tick an item when it is done; the review harness records it and removes the line._

## Next
- [ ] Decide how the app is priced: free, cheap, or something else. Not decided yet; on 2026-11-13 Peter said "really cheap or free - the point is to reinforce my presence as a developer" (from: Peter, 2026-11-16)
- [x] Peter: create a Developer ID Application certificate (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ +), back up its private key, and store notarization credentials with an app-specific password (from: release setup, 2026-11-16)
- [x] Release script: archive Release, export with Developer ID, notarize, staple, package a notarized DMG, check it with Gatekeeper (`spctl`) (from: release setup, 2026-11-16)
- [ ] Peter: install from the notarized DMG; check it opens with no warning, and that the privileged helper approves and works under the Developer ID signature (from: release setup, 2026-11-16)

- [ ] Give Debug builds their own bundle ID (ca.peter-jones.ActivityInspector.debug) and helper label, Mach service and code requirements, so a Debug build and the release never share background-item records; needs a project.pbxproj change (from: helper spawn failure, 2026-11-16)

## Later
- [ ] Decide whether to add a Disk Space page: what is using the disk, by folder; scanning is slow, so it needs care (moved to Later by Peter, 2026-11-15) (from: candidates list, 2026-11-14)
- [ ] Consider removing apps from Installed Apps (move to Trash, with a confirmation) (from: Peter, 2026-11-15)
- [ ] Distribute outside the App Store, after pricing is decided: the download page on activityinspector.com, payments and licences if it isn't free, and how updates reach users (no third-party dependencies, so not Sparkle unless that rule changes) (from: Peter, 2026-11-15)

## Undecided
