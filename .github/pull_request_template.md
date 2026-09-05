## What this changes

<!-- One or two sentences. Why the change was needed, not what the diff does. -->

## Checks

- [ ] `swift test` passes
- [ ] `swift format lint --strict --recursive --configuration .swift-format Sources Tests Package.swift` is clean
- [ ] `./build.sh` produces a bundle that launches
- [ ] If the UI changed: screenshot regenerated with
      `SCREENSHOT_OUTPUT=docs/screenshot.png swift test --filter Screenshot`
- [ ] If behaviour changed: `CLAUDE.md` and `CHANGELOG.md` updated to match

## Anything reviewers should look at closely

<!-- Keychain access, the token refresh, and the menu bar rendering all have
     non-obvious constraints documented in CLAUDE.md. Say so if you touched
     one of them. -->
