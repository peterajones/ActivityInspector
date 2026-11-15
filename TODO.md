# TODO

_Single source of truth for unfinished work in this project. Tick an item when it is done; the review harness records it and removes the line._

## Next
- [ ] Add tests for the Summary Memory card's zoomed graph: that MetricScale.zoomed gives at least a 1 GB band over the last minute and that the Available · Cached · Swap footer shows the right values. (from: review harness)
- [ ] Add a test for the Summary card layout in SummaryView, checking that the Temp, Power and GPU meters appear only where the Mac reports them and that the Top Processes card shares the leftover space. (from: review harness)
- [ ] Add tests for the Settings view's helper-status section and for each setting writing the same AppStorage key as its menu or popover counterpart (theme, saturation, bloom, show in menu bar, CPU time format). (from: review harness)
- [ ] Add tests for the Startup Apps enable/disable action: that enabling runs launchctl enable then bootstrap and disabling runs disable then bootout in gui/<uid>, and that nothing runs if the confirmation is declined. (from: review harness)
- [ ] Add tests for the System Info page's masking of identifying values (serials, hardware IDs, MAC addresses, user name) and for the ProfilerLabels lookup falling back when a loctable has no label. (from: review harness)

## Later
- [ ] App Store edition: add a sandboxed build of the app (Peter sets up the target/configuration in Xcode) with an APP_STORE compile flag that compiles out every private-API reader (SMC, IOReport, HID thermal, NetworkStatistics) and the helper, and hides Quit/Force Quit, Ports and Energy; see CLAUDE.md "Distribution" (from: Peter, 2026-11-13)
- [ ] App Store edition: after the design round, prepare App Store Connect (bundle ID, icon, screenshots, description, privacy details, price) and submit (from: Peter, 2026-11-13)

## Undecided
- [ ] Decide whether to pursue the shelved ESF activity/event feed and control-panel anchors (from: docs/superpowers/specs/2026-07-02-process-dashboard-design.md)
- [ ] Decide whether to add an Installed Apps page: every app with version, size, publisher (reuse CodePublisher) and where it came from, sortable and searchable; System Info's Applications data covers much of it (from: candidates list, 2026-11-14)
- [ ] Decide whether to add a Users page: accounts and who is logged in (from: candidates list, 2026-11-14)
- [ ] Decide whether to add a Disk Space page: what is using the disk, by folder; scanning is slow, so it needs care (from: candidates list, 2026-11-14)
- [ ] Decide whether to add a System Info export: copy or save a report of one item or all of them (deferred when System Info was built) (from: candidates list, 2026-11-14)
