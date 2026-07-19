#!/usr/bin/env bash
#
# fetch-sri.sh — download a file and verify it against a Subresource Integrity
# (SRI) hash before it is allowed to land on disk.
#
# The download always goes to a temp file first. The file is moved into place
# ONLY if its hash matches. A tampered or truncated download never touches your
# target path.
#
# Usage:
#   fetch-sri.sh <url> <dest> <sri-hash>     # download + verify, then place
#   fetch-sri.sh --print <url>               # download to temp, print its SRI,
#                                            # so you can pin the hash first
#
# <sri-hash> is the standard SRI form used in HTML: "<algo>-<base64digest>",
#   e.g.  sha384-QWTKZyjpPEjISv5WaRU9OFeRpok6YctnYmDr5pNlyT2bRjXh0JMhjY6hW+ALEwIH
# Supported algos: sha256, sha384, sha512.
#
# Where to get the official hash:
#   - jsDelivr:  on any file page, click "SRI" / copy the integrity="" value
#   - cdnjs:     the "Copy SRI" button next to each asset
#   - or generate one yourself from a copy you already trust with --print
#
# Examples:
#   fetch-sri.sh \
#     https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css \
#     webapp/static/bootstrap.min.css \
#     sha384-QWTKZyjpPEjISv5WaRU9OFeRpok6YctnYmDr5pNlyT2bRjXh0JMhjY6hW+ALEwIH
#
#   fetch-sri.sh --print https://example.com/some.js
#
set -euo pipefail

prog=$(basename "$0")

die()  { printf '%s: error: %s\n' "$prog" "$*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }

usage() {
  sed -n '3,32p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

# Compute an SRI string ("algo-b64digest") for a file.
compute_sri() {
  local algo=$1 file=$2 digest
  case "$algo" in
    sha256|sha384|sha512) ;;
    *) die "unsupported algorithm: $algo (use sha256, sha384, or sha512)";;
  esac
  command -v openssl >/dev/null 2>&1 || die "openssl not found; required for hashing"
  digest=$(openssl dgst -"$algo" -binary "$file" | openssl base64 -A)
  printf '%s-%s' "$algo" "$digest"
}

# Constant-time-ish string compare (avoids shell timing games; SRI is public
# anyway, but be tidy). Returns 0 if equal.
str_eq() { [ "$1" = "$2" ]; }

download() {
  local url=$1 out=$2
  command -v curl >/dev/null 2>&1 || die "curl not found"
  # -f: fail on HTTP errors; -S: show errors; -s: quiet; -L: follow redirects
  curl -fSsL --proto '=https' --tlsv1.2 -o "$out" "$url" \
    || die "download failed: $url"
}

# ---- arg parsing -----------------------------------------------------------

[ $# -ge 1 ] || usage 1
case "${1:-}" in
  -h|--help) usage 0 ;;
esac

tmp=$(mktemp "${TMPDIR:-/tmp}/fetch-sri.XXXXXX") || die "cannot make temp file"
trap 'rm -f "$tmp"' EXIT

if [ "${1:-}" = "--print" ]; then
  [ $# -eq 2 ] || die "--print takes exactly one <url>"
  url=$2
  note ">> downloading (to inspect, not placing anywhere): $url"
  download "$url" "$tmp"
  size=$(wc -c < "$tmp" | tr -d ' ')
  note ">> $size bytes received. SRI hashes:"
  for a in sha256 sha384 sha512; do
    printf '   %s\n' "$(compute_sri "$a" "$tmp")"
  done
  note ">> Pin one of the above, then re-run without --print to fetch+verify."
  exit 0
fi

# Normal mode: url dest sri
[ $# -eq 3 ] || die "expected 3 args: <url> <dest> <sri-hash>  (see --help)"
url=$1 dest=$2 sri=$3

# Split "algo-b64" -> algo, expected b64
case "$sri" in
  sha256-*|sha384-*|sha512-*) ;;
  *) die "hash must look like 'sha384-<base64>' (got: $sri)";;
esac
algo=${sri%%-*}

note ">> downloading: $url"
download "$url" "$tmp"

got=$(compute_sri "$algo" "$tmp")

if str_eq "$got" "$sri"; then
  destdir=$(dirname "$dest")
  [ -d "$destdir" ] || mkdir -p "$destdir"
  # move-into-place atomically on the same filesystem where possible
  mv -f "$tmp" "$dest" || die "verified, but could not write to: $dest"
  trap - EXIT
  # mktemp makes 0600; give the placed file normal read perms per the caller's
  # umask (e.g. 0644 with umask 022) so a web/server process can read it.
  mode=$(printf '%o' $(( 0666 & ~$(umask) )))
  chmod "$mode" "$dest" 2>/dev/null || true
  note ">> OK — integrity verified ($algo). Wrote: $dest"
  exit 0
else
  note ">> INTEGRITY MISMATCH — file REJECTED, nothing written."
  note "   expected: $sri"
  note "   actual:   $got"
  die "hash mismatch (possible tampering, wrong version, or corrupt download)"
fi
