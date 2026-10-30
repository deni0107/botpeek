# Security policy

## Reporting a vulnerability

Please **do not** open a public issue. Use
[GitHub private vulnerability reporting](https://github.com/deni0107/botpeek/security/advisories/new).
We aim to acknowledge reports within 7 days.

Please include the BotPeek version (`BotPeek --version`), macOS version, and steps to
reproduce. Do not include real message contents or credentials.

## Scope

Especially relevant:

- A reply delivered to the wrong bot or conversation, or sent twice.
- An approval performed without the user's explicit confirmation.
- BotPeek reading or storing more than documented (credentials, message text on disk).
- Keystrokes or clipboard contents reaching an app other than Grok Bot.
- Paths from Grok Bot's data escaping its folder (e.g. avatar keys).
- Supply-chain issues in the build and release workflows.

## Design commitments

BotPeek makes no network requests, has no servers, stores no message text, never writes
to Grok Bot's files, never reads credentials, and contains no secrets. Release signing
credentials live only in GitHub Actions secrets.

## Supported versions

Only the latest release receives fixes during the beta.
