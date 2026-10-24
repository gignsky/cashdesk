# CashDesk: how this fork works

Read this before touching anything. Claude Code loads it through `CLAUDE.md`;
other agents should read it too.

## What this repo is

CashDesk is a rebranded RustDesk client for Cash Consulting. It is a GitHub
fork of `rustdesk/rustdesk` at `github.com/gignsky/cashdesk`. The build plan
called the repo `cashconsults-support`; `cashdesk` is the name it got. Every
link, download URL and About-dialog reference uses `gignsky/cashdesk`.

- `master` mirrors upstream. Never commit to it; sync it with GitHub's "Sync fork".
- `cashconsults` is the integration branch, created from the newest upstream
  **release tag** (upstream tags are plain `1.5.0`, no `v`). Lord G. creates it
  and sets it as the default branch; feature branches start with `claude/` and
  are PRs into it. Until it exists, PRs target `master`.
- Releases are tags `cc-v<upstream>-<n>`, e.g. `cc-v1.5.0-1`. Upstream's own
  workflows only match `v1.2.3`-style tags, so a `cc-v` tag triggers only
  `.github/workflows/cashconsults-release.yml`, which builds Windows, Linux and
  Android and publishes a GitHub Release marked latest.

## The golden rule

Never hand-edit an upstream file to rebrand it. Every RustDesk-to-CashDesk
change goes through `brand/apply.sh`, which CI runs after checkout and before
the build. A rebase onto a new upstream release is therefore a rebase of the
`brand/`, `flake.*`, `CASHCONSULTS.md`, `CLAUDE.md` and workflow files only,
followed by rerunning the script. If a new user-visible "RustDesk" string turns
up, add a pattern to the script. Never commit the patched file.

The script requires each search pattern exactly once, fails loudly otherwise,
and is idempotent (a second run reports every edit as `present`). See
`brand/README.md`.

## Brand values and where they come from

| Value | Source |
| --- | --- |
| App name `CashDesk`, exe `CashDesk.exe` | repo variable `CC_APP_NAME` |
| Org `com.cashconsults`, Android id `com.cashconsults.cashdesk` | constants in `brand/apply.sh` |
| ID/relay server `remote.gignsky.com` | repo variable `RENDEZVOUS_SERVER` |
| Server public key | repo variable `RS_PUB_KEY` (contents of `id_ed25519.pub`) |
| Company `Cash Consulting`, maintainer `maxwell@cashconsults.com` | constants in `brand/apply.sh` |
| Icon | `brand/icon.svg`, the cashconsults.com favicon mark |

The private key `id_ed25519` never enters this repo, CI, a variable or a log.
Never invent, guess or paste a key: read `RS_PUB_KEY` from the repo variables
or ask.

## What must stay "rustdesk"

Renaming these breaks the build or the protocol: crate and module names,
`librustdesk.dll` / `librustdesk.so`, FFI and JNI symbols (the Android
`namespace` stays `com.carriez.flutter_hbb`; only `applicationId` changes),
translation keys in `src/lang/`, the `libs/hbb_common` submodule URL, the
`rustdesk` CLI binary name, and on Linux the package name, `rustdesk.service`
and the `/usr/share/rustdesk` install path. `build.py` and `res/DEBIAN/*`
hard-code those paths in dozens of places, so the `.deb` brands only what the
user sees. Side effect: CashDesk cannot be installed next to stock RustDesk on
the same Linux machine.

## What must never appear

- The RustDesk logo or name on a branded surface: window title, tray, About
  header, installer, launcher icon, file properties. RustDesk is a trademark.
  "Based on RustDesk (AGPL-3.0)" in copyright strings is the attribution the
  licence asks for and stays.
- Any update path to upstream builds. `apply.sh` short-circuits
  `check_software_update()` and `start_auto_update()`, and the app is a
  "custom client" (`APP_NAME != "RustDesk"`), which hides the update UI.

## AGPL duty

The About dialog links to this public repo, and the repo stays public. Every
release carries the source link in its body. Do not make the repo private.

## Build and test

- `nix develop` gives the Linux toolchain and helpers (`rustup`, Flutter,
  `gh`, `jq`, `nushell`, `imagemagick`, `librsvg`, `shellcheck`, `nixfmt`).
  Rust and Flutter versions are read from `.github/workflows/flutter-build.yml`
  at evaluation time; never hard-code them anywhere else.
- `RENDEZVOUS_SERVER=… RS_PUB_KEY=… CC_APP_NAME=CashDesk nix run .#apply-brand`
  patches the working tree. Run it twice, check `git diff --stat` is identical,
  then `git checkout -- . && git submodule foreach git checkout -- .`.
- `nix build .#brand-icons` regenerates the icon tree from `brand/icon.svg`;
  copy the result over `brand/icons/` and commit it. The committed copy exists
  because the Windows, Linux and Android runners have no nix.
- `nix flake check` runs shellcheck, nixfmt and the icon build. CI runs it on
  every PR (`cashconsults-check.yml`).
- Windows, Linux and Android binaries are built only by
  `cashconsults-release.yml` on a `cc-v*` tag. Nix never builds the Windows exe.

## Upgrading to a new RustDesk release

1. Sync `master` with upstream.
2. `git rebase --onto <new-tag> <old-tag> cashconsults`. Only `brand/`, the
   flake, the docs and the two `cashconsults-*.yml` workflows should be in the
   diff.
3. Run `apply.sh` locally; fix any `FAIL: expected exactly one match`.
4. Diff `cashconsults-release.yml` against upstream's new `flutter-build.yml`
   and copy changed steps and `env:` versions.
5. Tag `cc-v<new-upstream>-1`.

## Lord G.'s conventions

- Inspect `git status`, `git diff` and `git log` before staging. Stage files by
  name, never `git add -A`.
- Never commit secrets.
- Commit message, in order: descriptive title; `[ ] Reviewed by Lord G.`; a
  file-tree diff of what changed; host status; the agent's signature; `---`;
  additional context.
- Watch files for `#FERREN` / `#CLAUDE` tags. These are notes left for the agent.
- One phase per PR. Branch names start with `claude/`.

## Pointers

- Build plan: "CASH Consults Remote Support: Build Plan" (Claude doc, Oct 2026);
  the phases, acceptance list and open questions live there.
- `brand/README.md` for the script and icon pipeline.
- Website: `gignsky/cashconsults-website`; `/support/download` redirects to
  `https://github.com/gignsky/cashdesk/releases/latest/download/CashDesk.exe`.
