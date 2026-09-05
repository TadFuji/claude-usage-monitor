# Contributing

Thanks for taking a look. This is a small app with a small surface, so the bar
for a change is mostly: does it still build, do the tests still pass, and does
the diff say what it is for.

## Getting set up

```bash
git clone https://github.com/TadFuji/claude-usage-monitor.git
cd claude-usage-monitor
swift test          # 42 tests, no network, no Keychain
./build.sh          # assembles "Claude Usage Monitor.app"
swift run           # build and launch, without the .app bundle
```

You need macOS 13+ and a Swift toolchain. To see the app show real numbers you
also need the Claude Code CLI logged in with a subscription account — but you
do not need any of that to run the tests.

Run it against your own Keychain with:

```bash
pkill -f "Claude Usage Monitor.app"
./build.sh && cp -R "Claude Usage Monitor.app" /Applications/ && open "/Applications/Claude Usage Monitor.app"
```

A rebuild does not reach an already-running copy, and the app has no Dock icon,
so kill it first or you will be looking at the old one.

## Before you open a pull request

```bash
swift test
swift format lint --strict --recursive --configuration .swift-format Sources Tests Package.swift
```

CI runs the tests and `./build.sh` on two macOS versions, and the formatting
check on one. To fix formatting rather than just check it:

```bash
swift format --in-place --recursive --configuration .swift-format Sources Tests Package.swift
```

If you changed how anything looks, regenerate the README screenshot from the
real views rather than cropping one by hand:

```bash
SCREENSHOT_OUTPUT=docs swift test --filter Screenshot
```

Every value in that renderer is fixed, so re-running it on the same machine
rewrites the same bytes. It renders in both colour schemes and both languages.

## Things that look like cleanups but are not

`CLAUDE.md` is the long version. The short version:

- **The Keychain read spawns `/usr/bin/security` instead of calling
  `SecItemCopyMatching`.** This is not an oversight. The CLI rewrites the
  Keychain item every few hours and that write resets the item's ACL, so an
  in-process read re-prompts the user forever. `security` is Apple-signed and
  survives it.
- **`percent` is the quota consumed; the UI shows what is left.** Inverting one
  without the other is the easiest bug to introduce here, which is why several
  tests exist only to catch it.
- **A limit with no `percent` renders no ring at all.** Drawing an empty ring
  would read as "you are out of quota".
- **`.menuBarExtraStyle(.window)` is load bearing.** The default style renders
  the popover as a real `NSMenu`, which silently drops the shapes.
- **The app never spends the OAuth refresh token itself.** It runs the CLI and
  lets the CLI refresh, because getting this wrong can lock someone out of
  their own CLI.
- **`Strings` holds both languages as a value, not a resource bundle.** The
  bundle is assembled from two files by `build.sh`; a `.lproj` tree would be a
  third thing to keep in sync. Pass a `Strings` where you need a fixed language
  — that is how the tests avoid depending on the machine's locale.

### What the tests do not cover

Worth knowing before you trust a green run. The tests reach the models, the
view model, the colour scales, and the strings. They do **not** exercise SwiftUI
rendering, the Keychain, the network, `TokenRefresher`'s throttle, or the
`.menuBarExtraStyle(.window)` choice — all of which are load bearing and none of
which will complain if you break them. Changes in those areas need a real run:

```bash
pkill -f "Claude Usage Monitor.app"
./build.sh && cp -R "Claude Usage Monitor.app" /Applications/ && open "/Applications/Claude Usage Monitor.app"
```

## Reporting bugs

Use the issue templates — they ask for the three things that determine almost
every answer: your macOS version, how your Claude Code is authenticated, and
what the menu bar actually shows.

For anything that could expose someone's credentials, please follow
[SECURITY.md](SECURITY.md) instead of opening a public issue.

## Commits

Write the subject in the imperative ("Fix the reset time on the weekly ring"),
and use the body to say why the change was needed rather than restating the
diff. Nothing is enforced by a hook; it just makes `git log` worth reading.
