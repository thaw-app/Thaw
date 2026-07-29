# QA evidence

- Reproduced with Thaw Preview 5 on macOS 27 beta `26A5388g`, built-in display plus external Samsung display.
- On the external display, the first Dot click moved the mirrored item and the second click did not restore the section.
- Unified logging repeatedly reported `cgsGetScreenRectForWindow failed with error 1000`.
- `xcrun swiftc -parse` passes for all four changed Swift files.
- `MenuBarModel`: 27 tests passed.
- `ThawCapture`: 15 tests passed.
- Full app build and the 10-click external-display check require Xcode 27 CI output and remain pending.
