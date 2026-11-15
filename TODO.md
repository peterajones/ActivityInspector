# TODO

_Single source of truth for unfinished work in this project. Tick an item when it is done; the review harness records it and removes the line._

## Next
- [ ] Decide the free/paid split for the Full edition (TMOG-style: a capable free tier, paid features on top) and how licences unlock paid features in the one build (from: Peter, 2026-11-15)

## Later
- [ ] Decide whether to add a Disk Space page: what is using the disk, by folder; scanning is slow, so it needs care; a likely paid feature (moved to Later by Peter, 2026-11-15) (from: candidates list, 2026-11-14)
- [ ] Consider removing apps from Installed Apps (move to Trash, with a confirmation): a possible paid feature (from: Peter, 2026-11-15)
- [ ] Revisit the App Store with a purpose-built free version: something worth having inside the sandbox (a polished menu-bar monitor, say) that points people to the full app, not today's app with features removed; see CLAUDE.md "Distribution" (from: Peter, 2026-11-15)
- [ ] Distribute the Full edition outside the App Store: Developer ID signing, notarization, a download page, and how updates reach users (from: Peter, 2026-11-15)
- [x] App Store edition: add a sandboxed build of the app (Peter sets up the target/configuration in Xcode) with an APP_STORE compile flag that compiles out every private-API reader (SMC, IOReport, HID thermal, NetworkStatistics) and the helper, and hides Quit/Force Quit, Ports and Energy; see CLAUDE.md "Distribution": dropped, the sandboxed edition isn't a sellable product (Peter, 2026-11-15) (from: Peter, 2026-11-13)
- [x] App Store edition: after the design round, prepare App Store Connect (bundle ID, icon, screenshots, description, privacy details, price) and submit: dropped with the App Store edition (Peter, 2026-11-15) (from: Peter, 2026-11-13)

## Undecided
