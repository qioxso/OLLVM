#!/usr/bin/env bash
# Static VMP regression for the AArch64-only embedded interpreter.
set -euo pipefail

NDK="${1:?usage: run.sh <ndk-dir> <host>}"
HOST="${2:-linux-x86_64}"
EXT=""; case "$HOST" in windows-*) EXT=".exe" ;; esac
BIN="$NDK/toolchains/llvm/prebuilt/$HOST/bin"
CLANG="${CLANG:-$BIN/clang${EXT}}"
NM="$BIN/llvm-nm${EXT}"
READELF="$BIN/llvm-readelf${EXT}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT

COMMON=(--target=aarch64-linux-android21 -shared -fPIC -O2
        -fno-vectorize -fno-slp-vectorize)
VMP=(-mllvm -irobf -mllvm -irobf-vmp -mllvm -irobf-vmp-noinline
     -mllvm -irobf-vm_functions=vmp_named_mix)

"$CLANG" "${COMMON[@]}" "${VMP[@]}" -o "$OUT/vmp.so" "$HERE/vmp_smoke.c"
"$CLANG" "${COMMON[@]}" -o "$OUT/native.so" "$HERE/vmp_smoke.c"

vmp_symbols="$($NM -a "$OUT/vmp.so")"
native_symbols="$($NM -a "$OUT/native.so")"
sections="$($READELF -S -W "$OUT/vmp.so")"
fail=0

need_symbol() {
  if grep -q "$1" <<<"$vmp_symbols"; then
    echo "[ok]   found symbol: $1"
  else
    echo "[FAIL] missing symbol: $1"; fail=1
  fi
}

reject_symbol() {
  if grep -q "$1" <<<"$vmp_symbols"; then
    echo "[FAIL] unexpected symbol: $1"; fail=1
  else
    echo "[ok]   absent symbol: $1"
  fi
}

need_symbol 'gv_code_seg_vmp_annotated_mix'
need_symbol 'gv_code_seg_vmp_named_mix'
need_symbol 'vm_interpreter_vmp_annotated_mix_k'
need_symbol 'vm_interpreter_vmp_named_mix_k'
reject_symbol 'gv_code_seg_native_control'
reject_symbol 'gv_code_seg_unsupported_vector'

if grep -q 'gv_code_seg_' <<<"$native_symbols"; then
  echo '[FAIL] native control build contains a VMP bytecode blob'; fail=1
else
  echo '[ok]   native control build contains no VMP bytecode blob'
fi

for section in .s0 .s1 .s3; do
  if grep -q "${section}[[:space:]]" <<<"$sections"; then
    echo "[ok]   release VMP section present: $section"
  else
    echo "[FAIL] release VMP section missing: $section"; fail=1
  fi
done

if grep -q '\.AProtect\.' <<<"$sections"; then
  echo '[FAIL] release ELF still exposes an .AProtect section'; fail=1
else
  echo '[ok]   release ELF does not expose .AProtect section names'
fi

echo '[note] runtime semantics require an arm64 Android device; this test validates translation and packaging'
exit "$fail"
