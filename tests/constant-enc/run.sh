#!/usr/bin/env bash
# Exercise the level-3 constant encryption path on every packaged host compiler.
set -euo pipefail

NDK="${1:?usage: run.sh <ndk-dir> <host>}"
HOST="${2:-linux-x86_64}"
EXT=""; case "$HOST" in windows-*) EXT=".exe" ;; esac
BIN="$NDK/toolchains/llvm/prebuilt/$HOST/bin"
CLANG="${CLANG:-$BIN/clang${EXT}}"
READELF="$BIN/llvm-readelf${EXT}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT

"$CLANG" --target=aarch64-linux-android21 -shared -fPIC -O2 \
  -mllvm -irobf \
  -mllvm -irobf-cie -mllvm -level-cie=3 \
  -mllvm -irobf-cfe -mllvm -level-cfe=3 \
  -o "$OUT/encrypted.so" "$HERE/constant_enc.c"

sections="$($READELF -S -W "$OUT/encrypted.so")"
if ! grep -q '\.s1[[:space:]]' <<<"$sections"; then
  echo '[FAIL] level-3 constant encryption produced no protected data section'
  exit 1
fi
if grep -q '\.AProtect\.' <<<"$sections"; then
  echo '[FAIL] release ELF still exposes an .AProtect section'
  exit 1
fi

echo '[ok]   integer and floating-point level-3 encryption compiled'
echo '[ok]   protected data uses the release section name .s1'
