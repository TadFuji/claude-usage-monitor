# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS menu bar app (SwiftUI `MenuBarExtra`) that displays the current user's
Claude Code usage quota. It is a status-bar-only app (`LSUIElement` = true, no
Dock icon). The UI strings are in Japanese.

## Build & run

```bash
swift test                      # 42 tests: decoding, quota maths, colours, strings, backoff
./build.sh                      # compile + assemble "Claude Usage Monitor.app" bundle
swift run                       # build & launch for local iteration
swift format lint --strict --recursive --configuration .swift-format Sources Tests Package.swift
```

`build.sh` runs `swift build -c release`, then assembles the bundle from two
copies: the binary and `Info.plist`. The app ships no image asset — the menu bar
glyph is an SF Symbol resolved at runtime. Install with
`cp -R "Claude Usage Monitor.app" /Applications/`. A locally built bundle carries
no quarantine flag and opens normally; only a downloaded copy needs the
right-click → Open dance.

CI (`.github/workflows/ci.yml`) runs `swift test` and `./build.sh` on two macOS
versions plus a `swift format` check; `.github/workflows/release.yml` builds,
zips and publishes a GitHub Release when a `v*` tag is pushed.

A rebuild does not reach an already-running instance, and the app is easy to
forget because it has no Dock icon. Kill it first, and reinstall if the copy in
`/Applications` is the one that actually runs:

```bash
pkill -f "Claude Usage Monitor.app"
./build.sh && cp -R "Claude Usage Monitor.app" /Applications/ && open "/Applications/Claude Usage Monitor.app"
```

`.gitignore` excludes `.build/`, the whole `Claude Usage Monitor.app/` bundle,
and local working notes (`.claude/`, `handoff.md`), so a rebuild does not dirty
the tree. Everything else tracked is the source of truth.

## Architecture

Data flows in one direction: Keychain → API → model → view model → SwiftUI.

- **`KeychainService`** reads the logged-in Claude Code OAuth token from the
  macOS Keychain — generic-password item with service name
  `Claude Code-credentials`, whose data is JSON at `claudeAiOauth.accessToken`.
  No token is stored by this app; it reuses the Claude Code CLI's credentials.
  It reads by spawning `/usr/bin/security find-generic-password -w`, **not**
  `SecItemCopyMatching`, and that is not interchangeable. The CLI rewrites this
  item with `security add-generic-password -U` on every token refresh (~8h), and
  each write resets the item's ACL partition list to `apple-tool:` alone — which
  wipes the `cdhash:` entry that "Always Allow" adds for this app. Reading in
  process therefore re-prompted every ~8h forever (`/usr/bin/log show --predicate
  'process == "securityd"'` shows the `ACL partition mismatch` / `adding XARA
  partition` pairs), and the modal froze the poll loop until dismissed. Being
  adhoc-signed, the app has no stable identity to register anyway: every
  `./build.sh` changes the cdhash and would need its own approval. `security` is
  Apple-signed, matches `apple-tool:`, and survives the rewrites — it is also how
  the CLI itself reads the item back. Do not "simplify" this into the Security
  framework.
- **`UsageService`** GETs `https://api.anthropic.com/api/oauth/usage`. It
  **impersonates the Claude Code client**: `Authorization: Bearer <token>`, the
  `anthropic-beta: oauth-2025-04-20` header, and a `claude-code/<version>`
  User-Agent. `clientVersion` is hardcoded (`"2.0.32"`) and was still accepted on
  2026-08-30 against a CLI that had reached `2.1.251` — a `401` was reproduced
  identically under both, so **do not read an auth failure as a stale version**
  (see the 401 note at the end). A `429` becomes `rateLimited(retryAfter:)`
  carrying the parsed header, kept apart from the other statuses because it
  changes what the app does next rather than only what it says. And
  `fetch(allowRefresh:)` carries the once-only flag that stops the 401 retry
  recursing — `TokenRefresher`'s 30-minute throttle is a budget, not a
  termination guarantee.
- **`Models.swift`** decodes only the response's `limits` array — one entry per
  quota window, each with `kind` (`session`, `weekly_all`, `weekly_scoped`),
  `percent`, `resets_at`, and an optional `scope.model.display_name`. The older
  top-level fields (`five_hour`, `seven_day`, `seven_day_opus`,
  `seven_day_sonnet`) are deliberately ignored: opus/sonnet now come back `null`,
  and the model-scoped window that is usually the real constraint appears *only*
  in `limits`. Key gotcha: `percent` is the quota **already consumed** (0–100);
  the UI shows **remaining** (`100 - percent`) via `remainingPercentage`, which
  stays `nil` when the API sends no figure so the ring is skipped rather than
  drawn empty (an empty ring reads as "exhausted"). Do not key limits off
  `scope.model.id` (null in every response observed so far) or `resets_at`
  (microseconds differ between limits that share a reset) — `ForEach` uses the
  array index.
- **`UsageViewModel`** (`@MainActor`, `ObservableObject`) owns a single polling
  `Task`. Each `fetchOnce()` returns how long to wait before the next one, so a
  `429` can push the next poll out to the server's `Retry-After` (floored at the
  5-minute `refreshInterval`, capped at `maximumBackoff`). `refresh()`
  intentionally restarts the whole loop rather than firing a one-off fetch — so
  manual refresh also resets the timer and cancels any in-flight HTTP request
  (not the Keychain read or a running CLI refresh, neither of which is
  cancellable). `visibleLimits` — not the view — decides that a window without a
  `percent` is not drawn.
- **`Strings.swift`** holds both languages as a value rather than a `.lproj`
  bundle — `build.sh` assembles the app from two files and a resource tree would
  be a third. `Strings.current` picks Japanese for a Japanese system and English
  otherwise; every user-visible call site takes a `Strings` so it can be pinned.
- **`QuotaColor`** is the two colour scales, deliberately outside the views so
  they are testable: the menu bar warns earlier (below 60) than the rings do
  (below 50), because the menu bar is the only thing most people look at.
- **`ClaudeUsageMonitorApp`** is the entry point + all views. Each limit renders
  as a `UsageRing` (a trimmed `Circle`); `.menuBarExtraStyle(.window)` is load
  bearing — the default `.menu` style renders the content as a real NSMenu and
  silently drops shapes and stack layout. The menu bar itself shows no number:
  it is the `asterisk` SF Symbol tinted by the *session* window's remaining quota
  (≥60 green, 40–59 yellow, <40 red). Tinting means pre-rendering an `NSImage`
  with `isTemplate = false`, because `MenuBarExtra` renders its label as a
  template image and strips color. `viewModel.menuBarText` (`C<remaining%>` /
  `C--` / `C..`) is belt-and-braces for a system without the symbol; every macOS
  this app supports has it, so that branch does not run in practice. The tinted
  image carries an `accessibilityDescription` with the actual number, because
  the colour is the whole message and VoiceOver cannot see colour. The rings inside the popover use a different scale (≥50 green,
  20–49 orange, <20 red).

When changing the response shape, update `UsageResponse`/`UsageLimit` in
`Models.swift` and `UsageLimit.label` (which maps `kind` to the Japanese caption)
together — and `Tests/UsageLimitTests.swift`, whose fixture is a stand-in for a
real payload.

The tests live in `Tests/` and cover only what can be checked without a token:
decoding (including `percent` arriving as either an integer or a float), the
consumed→remaining conversion and its clamping, label mapping, timestamp
parsing, both colour scales, both languages, `Retry-After` parsing, and the
backoff it feeds. Verified by mutation rather than assumed: inverting
`remainingPercentage` fails 9, swapping a menu bar colour fails 4, dropping the
`visibleLimits` filter fails 2, clearing `usage` on a failed fetch fails 1, and
treating an unreadable `Retry-After` as zero fails 3.

Two seams exist for the tests: `UsageViewModel(startPolling:fetch:)` substitutes
the fetch and keeps the network loop off, and anything user-visible takes a
`Strings` so assertions do not depend on the machine's locale. What the tests do
*not* reach — SwiftUI rendering, the Keychain, the network, `TokenRefresher`'s
throttle, `.menuBarExtraStyle(.window)` — is listed in `CONTRIBUTING.md`; a green
run says nothing about those.

`Tests/ScreenshotTests.swift` is not a test: it re-renders the three README
screenshots (English light and dark, Japanese light) from the real views, and
skips unless `SCREENSHOT_OUTPUT` names a directory. Every value in it is fixed,
so a regeneration on the same machine rewrites identical bytes.

An `HTTP 401` means the Keychain's OAuth token has expired — the single most
likely failure (one measured token was valid for 8 hours). On a 401,
`TokenRefresher` runs the claude CLI once (`claude -p ... --model haiku` via a
login shell, so PATH resolves) and retries the fetch; the CLI refreshes the
Keychain token as a side effect, verified 2026-08-31 — before the spawn was
reworked, so that observation covers the refresh, not the details below. Two of
those details are load bearing: the shell line is `exec claude …`, so the
90-second watchdog signals the CLI itself rather than a wrapper shell, and the
watchdog escalates SIGTERM → SIGKILL after 10 more seconds. The escalation is
defensive — a CLI that traps SIGTERM for cleanup would otherwise leave
`waitUntilExit()` blocked forever; it has not been observed doing so. It also
runs with an app-owned working directory
(`~/Library/Application Support/ClaudeUsageMonitor`), which does not stop the CLI
filing a transcript per run — it moves those transcripts out of
`~/.claude/projects/-/` and into one folder named after that directory.
Attempts are throttled to one per 30 minutes — that throttle is also the recursion guard on the retry.
The app deliberately never spends the stored refresh token itself, because that
could lock the user out of the CLI. Each auto-refresh consumes one tiny haiku
call of subscription quota: ~3/day in normal operation (the token lives ~8h), but
a login that stays broken fires one every 30 minutes — up to ~48/day.

Two failure modes route around that 401 path. A locked login keychain makes
`security` hit its 10-second watchdog, so the fetch fails as `noToken` ("認証情報が
見つかりません") and never triggers the CLI refresh — that message means "locked or
missing", not only "never logged in". And `TokenRefresher.lastAttempt` lives in
memory, so quitting and relaunching the app clears the 30-minute throttle.

A persistent `429` with `retry-after` has one observed cause: many Claude Code
sessions alive at once (a dozen or so, mostly spawned by the desktop app)
exhausting the per-account budget on this endpoint — not a stale UA, not this
app's 5-min poll. The app honours `Retry-After` (floored at the poll interval,
capped at an hour) so it stops adding to the pile, but the actual fix is still
manual: close sessions / restart the desktop app.

## Inspecting the live response

The response shape drifts — windows are added and retired — and it is only
visible with a real token, so a throwaway Swift file that reuses
`KeychainService.getOAuthToken()` and prints the body is the fastest way to see
the current shape. Keep the token out of stdout. On 2026-08-30 the payload carried
three `limits` entries (`session`, `weekly_all`, and one `weekly_scoped`) next to
a dozen or so mostly-null top-level fields under upstream code names that this
app ignores. Note `percent` arrived as an integer while the sibling `utilization`
was a float, so `UsageLimit.percent` is decoded as `Double?` to survive either.

When reaching for the unified log to debug the Keychain prompts, spell it
`/usr/bin/log`: zsh has a builtin of the same name that fails with `too many
arguments`.
