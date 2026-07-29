---
recorded_at: 2026-07-29T05:14:59.894Z
by: claude
verdict: concerns
mode: full
finding_ids: shared-reveal-order#p1
simulation_verdict: trace_inadequate
spec_hash: acd9d74fa181
code_patch_id: c95811d4f6f3f4ea1db0b0bb40dc4ca8f3e457efc052ab2155ff99d76bfb9deb
code_diff_hash: 52bd156871f9d66c1c614939c2f52f496efd0515e88450d300ba2cb9639c340f
head_sha: 1ae1e803b882bd11224daf5e11e2e983b2896281
confusion: |
  (none)
assumptions: |
  Static read-only review; patched app not yet hardware-tested.
notes: |
  Secondary-display protection was only wired through Dot toggle; hover, scroll, empty-menu-bar and always-hidden reveal paths could still synchronize order. Moved pointer-display decision into MenuBarSection.show and covered direct always-hidden controller calls.
---
---
recorded_at: 2026-07-29T05:18:55.009Z
by: claude
verdict: concerns
mode: delta
finding_ids: none
simulation_verdict: trace_inadequate
spec_hash: acd9d74fa181
code_patch_id: cefd8232d61b5a0cb687aee7e14c22d4c0783ba32cd6180a28fc57ac44beaa00
code_diff_hash: 52bd156871f9d66c1c614939c2f52f496efd0515e88450d300ba2cb9639c340f
head_sha: 1ae1e803b882bd11224daf5e11e2e983b2896281
confusion: |
  Could not prove the macOS 27 primary-action registration fallback frequency or event lifetime without an Xcode 27 build.
assumptions: |
  Static review; local swift parse and package suites pass, full app build requires Xcode 27.
notes: |
  [debt:live-mouse-sampling#p1,wiring-untested#p1] Follow-up confirms the shared fix covers click, hover, scroll, show-on-click, hotkey semantics, and both direct always-hidden paths. Remaining p1 concerns are event-time sampling under rare legacy fallback and lack of full Xcode 27/hardware validation; keep Draft until CI and physical validation.
---
