# Security policy

## Macscout is not a medical device

Macscout displays glucose data from **your** Nightscout site and plays local
alerts. It is an open-source convenience client, **not** an FDA/CE medical
device, and must not be the only system you rely on for treatment decisions.

If you believe a bug could cause a **wrong, missing, or delayed** reading or
alert in a way that might affect someone's safety, please treat it as a
security/safety report and follow the process below.

## Supported versions

| Version | Supported |
|---|---|
| Latest release on [GitHub Releases](https://github.com/thiagomsoares/macscout/releases) | ✅ |
| Builds from `main` | best-effort |
| Older releases | ❌ — please upgrade |

## What to report

Please report:

- Secrets (Nightscout token / API secret) leaving the Keychain or appearing in logs, screenshots defaults, or crash reports
- Network calls to unexpected hosts
- Path traversal or arbitrary file write/read outside the intended scope
- Updates / download flows that could be redirected to untrusted binaries
- Anything that could display a stale or fabricated reading as if it were fresh
- Anything that could suppress an urgent alert without a clear user action

## What not to file publicly

Do **not** open a public GitHub issue for the items above. Use private reporting.

## How to report

Email the maintainer:

**thiagomsoares@users.noreply.github.com**

Subject line: `[Macscout security] short summary`

Include:

1. A description of the issue and its impact
2. Steps to reproduce (or a proof of concept)
3. Affected version / commit
4. Any suggested fix, if you have one

You can also use
[GitHub Private Vulnerability Reporting](https://github.com/thiagomsoares/macscout/security/advisories/new)
if it is enabled on the repository.

Please **redact** real Nightscout URLs, tokens, API secrets, and any personal
health data.

## Response expectations

- Acknowledgement within **72 hours** when possible
- A reasoned timeline for a fix once the issue is confirmed
- Credit in the fix notes if you want it (say so in the report)

## Safe harbor

We will not pursue legal action against researchers who:

- Make a good-faith effort to avoid privacy violations and service disruption
- Do not access or exfiltrate other users' data
- Report promptly and keep the issue confidential until a fix is released
  (or we explicitly say it is OK to disclose)

Thank you for helping keep people with diabetes — and their data — safer.
