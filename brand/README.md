# CashDesk branding

Everything that turns the RustDesk tree into CashDesk lives here. Nothing in
this directory is applied in git; CI runs `brand/apply.sh` after checkout and
before every build, and developers run it locally to test. Upstream files are
never committed in their patched form, so rebasing onto a new RustDesk release
is `git rebase` plus rerunning the script.

## Files

| File | Purpose |
| --- | --- |
| `apply.sh` | The one idempotent script. Reads `RENDEZVOUS_SERVER`, `RS_PUB_KEY`, `CC_APP_NAME` from the environment. |
| `icon.svg` | The CashDesk mark (the cashconsults.com favicon). Only source of every icon. |
| `gen-icons.py` | Renders `icon.svg` into `icons/`. Uses `rsvg-convert` when present, else Playwright Chromium. |
| `icons/` | Rendered icons, committed because the Windows/Android runners have no nix. Paths mirror the repo. |

## Running

```sh
RENDEZVOUS_SERVER=remote.gignsky.com RS_PUB_KEY='<id_ed25519.pub contents>' CC_APP_NAME=CashDesk \
  bash brand/apply.sh
# or, inside the devShell:
nix run .#apply-brand
```

Run it twice: the second run must report every edit as `present` and change
nothing. Afterwards restore the tree with
`git checkout -- . && git submodule foreach git checkout -- .`.

Every text edit asserts its search pattern occurs exactly once in the target
file. When upstream changes a line, the script stops with `FAIL: expected
exactly one match` and names the file: update the pattern here, never patch
the upstream file by hand.

## Regenerating icons

```sh
nix build .#brand-icons && rm -rf brand/icons && cp -r result brand/icons && chmod -R u+w brand/icons
# without nix (uses the local Playwright Chromium):
python3 brand/gen-icons.py --out brand/icons
```

Pixel output differs slightly between the two rasterizers (anti-aliasing), so
regenerate with one of them and commit the result; do not expect byte equality.

## Secrets

`RS_PUB_KEY` is the **public** half of the server key pair (`id_ed25519.pub`,
44 base64 characters). The script refuses anything that does not look like
that. The private key `id_ed25519` never enters this repository, CI, or any
variable.
