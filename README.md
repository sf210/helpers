# helpers

Small, self-contained command-line helpers. No dependencies beyond common
Unix tools (`bash`, `curl`, `openssl`).

## `fetch-sri.sh` — download a file and verify its integrity before saving it

Downloading an asset from a CDN with plain `curl`/`wget` gives you no guarantee
you got the file the author published — a compromised CDN, a hijacked URL, a
man-in-the-middle, or a silent truncation all produce a file that *looks* fine.

`fetch-sri.sh` closes that gap. It downloads to a temporary file, computes the
file's [Subresource Integrity](https://developer.mozilla.org/docs/Web/Security/Subresource_Integrity)
(SRI) hash, and **moves it into place only if the hash matches**. On a mismatch
it writes nothing and exits non-zero — a tampered or corrupt download never
reaches your target path.

### Install

Already on this machine. The script is executable and aliased in `~/.bashrc`:

```bash
alias fetch-sri='~/repos/helpers/fetch-sri.sh'
```

Run `source ~/.bashrc` (or open a new shell) to pick up the alias.

### Usage

```
fetch-sri <url> <dest> <sri-hash>    # download, verify, then place at <dest>
fetch-sri --print <url>              # download to a temp file, print its SRI
fetch-sri --help
```

`<sri-hash>` is the standard HTML integrity form: `<algo>-<base64digest>`, where
`<algo>` is `sha256`, `sha384`, or `sha512`. Example:

```
sha384-QWTKZyjpPEjISv5WaRU9OFeRpok6YctnYmDr5pNlyT2bRjXh0JMhjY6hW+ALEwIH
```

### Where to get the official hash

Pin the hash **published by the source**, not one you generated from the same
download (a bad download would just verify against itself):

- **jsDelivr** — on any file page, copy the `integrity="..."` value from the
  HTML/SRI tab.
- **cdnjs** — use the "Copy SRI" button next to each asset.
- **Self-generated** — if you already have a copy you trust, `--print` gives you
  the hash to lock future downloads against.

### Examples

Fetch + verify + place:

```bash
fetch-sri \
  https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css \
  webapp/static/bootstrap.min.css \
  sha384-QWTKZyjpPEjISv5WaRU9OFeRpok6YctnYmDr5pNlyT2bRjXh0JMhjY6hW+ALEwIH
```

Discover the hash first, then pin it:

```bash
fetch-sri --print https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js
# >> 80721 bytes received. SRI hashes:
#    sha256-CDOy6cOibCWEdsRiZuaHf8dSGGJRYuBGC+mjoJimHGw=
#    sha384-YvpcrYf0tY3lHB60NNkmXc5s9fDVZLESaAA55NDzOxhy9GkcIdslK1eN7N6jIeHz
#    sha512-7Pi/otdlbbCR+LnW+F7PwFcSDJOuUJB3OxtEHbg4vSMvzvJjde4Po1v4BR9Gdc9aXNUNFVUY+SK51wWT8WF0Gg==
```

### Behavior notes

- Downloads over HTTPS only (`--proto '=https' --tlsv1.2`), follows redirects,
  fails on HTTP errors.
- On a hash **mismatch**: nothing is written to `<dest>`, the temp file is
  removed, and the exit code is non-zero — safe to use in scripts with `set -e`.
- Creates the destination directory if it doesn't exist.
- The placed file gets normal read permissions per your `umask` (e.g. `0644`
  with `umask 022`), so a web/server process can read it.

### Requirements

`bash`, `curl`, `openssl` — all standard on this system.
