# TODO

_Single source of truth for unfinished work in this project. Tick an item when it is done; the review harness records it and removes the line._

## Next
- [x] Decide whether to pursue the shelved ESF activity/event feed and control-panel anchors: dropped both (Peter, 2026-11-15) (from: docs/superpowers/specs/2026-07-02-process-dashboard-design.md)
- [x] Decide whether to add an Installed Apps page: every app with version, size, publisher (reuse CodePublisher) and where it came from, sortable and searchable; System Info's Applications data covers much of it: adding it now (Peter, 2026-11-15) (from: candidates list, 2026-11-14)
- [x] Build the Installed Apps page: a sidebar item with a sortable, searchable table of apps (version, kind, origin, publisher, size, modified) and a detail pane, from system_profiler's Applications data (from: Peter, 2026-11-15)
- [ ] Decide whether to add a Users page: accounts and who is logged in (from: candidates list, 2026-11-14)
- [ ] Decide whether to add a Disk Space page: what is using the disk, by folder; scanning is slow, so it needs care (from: candidates list, 2026-11-14)
- [ ] Decide whether to add a System Info export: copy or save a report of one item or all of them (deferred when System Info was built) (from: candidates list, 2026-11-14)

## Later
- [ ] App Store edition: add a sandboxed build of the app (Peter sets up the target/configuration in Xcode) with an APP_STORE compile flag that compiles out every private-API reader (SMC, IOReport, HID thermal, NetworkStatistics) and the helper, and hides Quit/Force Quit, Ports and Energy; see CLAUDE.md "Distribution" (from: Peter, 2026-11-13)
- [ ] App Store edition: after the design round, prepare App Store Connect (bundle ID, icon, screenshots, description, privacy details, price) and submit (from: Peter, 2026-11-13)

## Undecided
