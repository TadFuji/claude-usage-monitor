# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-09-05

First public release.

### Added

- Menu bar item showing the remaining quota of the current session window, as
  an asterisk tinted green, yellow, or red.
- A popover with one ring per quota window the API reports — session, weekly,
  and any model-scoped window — each with its remaining percentage and reset
  time.
- Automatic recovery from an expired session: on `HTTP 401` the app runs the
  Claude Code CLI once so the CLI refreshes its own Keychain token, throttled
  to one attempt per 30 minutes.
- Japanese and English interface, following the system language.
- Backoff on `HTTP 429`: the app waits as long as the server's `Retry-After`
  asks, never below its own poll interval and never above an hour.
- VoiceOver descriptions for the menu bar item and for each ring, since the
  colour of the glyph is otherwise the only thing carrying the state.
- 42 tests covering response decoding, the consumed-versus-remaining
  conversion, both colour scales, both languages, `Retry-After` parsing, and the
  menu bar's display states.

### Notes

- The app reads the OAuth token the Claude Code CLI stores in the Keychain and
  never stores a credential of its own.
- The usage endpoint it reads is undocumented, so this release can stop working
  without anything changing on this side.

[Unreleased]: https://github.com/TadFuji/claude-usage-monitor/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/TadFuji/claude-usage-monitor/releases/tag/v1.0.0
