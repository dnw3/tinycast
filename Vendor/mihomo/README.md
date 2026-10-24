# mihomo core

The proxy feature runs [mihomo](https://github.com/MetaCubeX/mihomo) as a separate process. The user
approved it as a bundled dependency on 2026-10-21 (decisions D1, D6 and D8 in
[the proxy spec](../../docs/plans/proxy-spec.md)). Tinycast never links it: the app and the TUN helper
only start it and talk to its REST controller over a Unix socket.

- Version and SHA-256 per architecture: [`core.env`](core.env), the one place they are written. Only
  official release builds are used, unmodified: `mihomo-darwin-arm64-<tag>.gz` and
  `mihomo-darwin-amd64-compatible-<tag>.gz`.
- Licence: GPL-3.0. `mihomo-LICENSE` is the upstream `LICENSE` file of the pinned tag, unmodified, and
  ships in the app resources; `NOTICE.md` names the version and links its source.

## Building

The binary is not committed. `Scripts/fetch-mihomo.sh` downloads the pinned release for this Mac, checks
it against `core.env`, keeps the archive and unpacks the core into `build/vendor/mihomo/`. The Tinycast
target's "Embed mihomo" build phase copies it to `Contents/Helpers/mihomo` and signs it with the app's
identity, adding the hardened runtime where the app has it. A build made without fetching still
succeeds; the proxy then reports that no core is present until one is downloaded in the app.

## Upgrading the bundled core

```sh
Scripts/upgrade-mihomo.sh --check     # the pinned and the latest release; changes nothing
Scripts/upgrade-mihomo.sh             # move to the latest release
Scripts/upgrade-mihomo.sh v1.19.33    # or to a named one
```

The script reads the release from GitHub's API (through `gh`'s token when there is one), downloads both
archives and checks each against the SHA-256 GitHub publishes for it, then makes sure the binary reports
the tag and architecture it should. It compares the upstream `LICENSE`, rewrites `core.env` and the
version in `NOTICE.md`, unpacks the new core and runs `Scripts/proxy-smoke.sh`. Any failure puts the old
pin, notice, licence and binary back. What is left to do is review and commit the changed files.

The smoke test drives the shipped `ProxyManager` against the pinned core on loopback fixtures: it
downloads and installs the core in-app from a local copy of the release feed, checks every routing
feature, checks the TUN config with `-t`, and walks a failed in-app update through its rollback.

## Updating in the app

Users get newer cores without a new Tinycast build. `ProxyManager` checks GitHub for the latest official
release, verifies its published SHA-256, confirms the version with `-v` and the current config with `-t`,
and keeps it under `Proxy/Releases/<tag>/` beside the bundled core. The newest of the two runs; one that
fails to start right after an update is removed and the previous core started again. Restoring the
bundled core deletes every download. Settings › Proxy › General › Core drives it once the settings pages
land (plan P5); the spec's "内核更新" section has the details.
