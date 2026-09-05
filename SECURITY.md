# Security Policy

## Reporting a vulnerability

Please report security issues through GitHub's private vulnerability
reporting: open the **Security** tab of this repository and choose **Report a
vulnerability**. That keeps the report private until a fix exists. Please do
not open a public issue for anything that could expose someone's credentials.

This is a personal project maintained in spare time. Expect a first response
within a couple of weeks rather than a couple of hours.

## What this app does with your credentials

Worth knowing before you audit it, and worth checking if you think something
is wrong:

- **It stores no credentials of its own.** It reads the OAuth access token
  that the Claude Code CLI keeps in the macOS Keychain (generic-password item
  `Claude Code-credentials`) and holds it only for the duration of one HTTPS
  request.
- **The token leaves the machine only to `api.anthropic.com`**, over HTTPS, as
  an `Authorization: Bearer` header. `NSAllowsArbitraryLoads` is `false`, so
  cleartext HTTP is refused.
- **The token never reaches the process list or a log.** The Keychain read
  spawns `/usr/bin/security` directly rather than through a shell, and the
  secret comes back on stdout — never in `argv`. The app writes no log file of
  its own and prints no token.
- **It never spends the stored refresh token.** On an expired session it runs
  the Claude Code CLI once and lets the CLI do the refresh (see the README).
- **It runs one external command with your privileges**: `claude`, resolved
  from your PATH through a login shell. Nothing in the API response influences
  that command.

## Scope

In scope: anything that could leak the token, run unintended code, or let a
malicious API response affect the host.

Out of scope: the upstream endpoint's own behaviour, rate limiting, and the
fact that the endpoint is undocumented and may break.
