# Security

## Threat model

HermesAgent exposes a local HTTP service. Localhost is not treated as fully trusted: browser content, other user-space processes, and malware on the same account can attempt to reach `127.0.0.1:<port>`.

## Required controls

- Bind only to `127.0.0.1`; never bind to `0.0.0.0`.
- Generate a random 32-byte token on first launch.
- Store the token at `~/Library/Application Support/HermesAgent/auth_token`.
- Set token file permissions to `0600` and data directory permissions to `0700` where possible.
- Open the browser with `http://127.0.0.1:<port>/?token=...` only as an initial handoff.
- Runtime should immediately move the token into an HTTP-only same-site cookie or equivalent session storage and redirect away from the token URL.
- Require token authentication for `/health` and all API endpoints.
- Restrict CORS to the active localhost origin only.
- Never persist API keys or auth provider secrets in `UserDefaults`, plist files, logs, diagnostics archives, or source code.
- Store provider secrets in Keychain with explicit accessibility and macOS data protection keychain enabled.

## Current fallback runtime

`HermesAgent/Resources/runtime/server/index.js` is a secured fallback runtime for local launcher testing. It verifies:

- `127.0.0.1` binding.
- bearer/query/cookie token auth.
- unauthorized `/health` returns `401`.
- authorized `/health` returns `200`.
- browser handoff with `?token=` returns `302` and sets an HTTP-only cookie.
- no-store cache headers and restricted CORS.

Production releases should replace the fallback runtime with the real HermesAgent server via `Scripts/bundle-runtime.sh`. The real server must keep the same security guarantees.

## Diagnostics

Diagnostics export may include logs and non-secret configuration only. API keys, OAuth tokens, auth tokens, passwords, cookies, and environment secrets must be redacted or omitted.

## Reporting

Please report vulnerabilities privately before opening a public issue. Include reproduction steps, affected version, macOS version, and whether the issue requires local access or remote browser content.

## Out of scope

- Attacks requiring full local admin compromise.
- Modified or unsigned builds not produced by the release pipeline.
- Vulnerabilities in user-installed custom Node runtimes.
