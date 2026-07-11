#!/usr/bin/env bash
# szl/mayhem/build.sh — build the szl interpreter as the fuzz target, plus a clean normal-flags
# build of the same binary for szl's own known-answer test suite (mayhem/test.sh).
#
# szl is a tiny embeddable Tcl-/shell-like scripting language in C. The Mayhem target is FILE-INPUT
# (CLI): `szl @@` runs the fuzz bytes as a script through the interpreter — the whole parser +
# evaluator + builtin command set. This is the natural fuzz surface (matches the old integration's
# `szl /test.szl` target). No libFuzzer harness: the szl binary IS the file-input target and its own
# standalone reproducer (like the cproc reference).
#
# MINIMAL build: szl's standard library has many OPTIONAL extensions that pull in heavy system libs
# (openssl/zlib/libffi/libcurl/libarchive) or git submodules (ed25519/lzfse/zstd). We disable all of
# them — the fuzz surface we care about is the interpreter core + the always-present builtins, and a
# minimal build keeps deps to just meson+pkg-config. The one submodule we must fetch is `linenoise`
# (line editing): meson's linenoise option has no `no` choice, so its source must be present. We build
# with -Dbuiltin_all=true so everything links statically into a single self-contained `szl` executable
# (a shared-lib build can't link the ASan/UBSan runtime into the loadable .so extensions).
#
# Two builds from the same source tree (separate build dirs), done sequentially:
#   (1) NORMAL-flags build -> /mayhem/build-tests/szl  (honest oracle for test.sh; no sanitizer noise)
#   (2) SANITIZED build     -> /mayhem/szl              (the fuzz target; project built WITH $SANITIZER_FLAGS)
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the ENV, overridable. SANITIZER_FLAGS uses `=` (not `:=`) so an explicit empty value
# (--build-arg SANITIZER_FLAGS=) is honored → no-sanitizer build (the interpreter's natural crash).
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
# DEBUG_FLAGS carries DWARF debug info independently of the sanitizer off-switch. DWARF must be < 4
# (Mayhem triage can't read >= 4); clang-19's plain `-g` emits DWARF-5, so -gdwarf-3 is explicit.
# Applied to BOTH compile and link of the fuzz/standalone build (NOT the test-oracle build).
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS DEBUG_FLAGS CC MAYHEM_JOBS

cd "$SRC"

# linenoise has no `with_linenoise=no` option and is a submodule (its source must exist). Fetch only it;
# all other submodule-backed extensions (ed25519/lzfse/zstd) are disabled below so we never need them.
git config --global --add safe.directory "$SRC" 2>/dev/null || true
git submodule update --init src/linenoise

# Every optional extension OFF: the auto-detected system-lib exts (tls/zlib/ffi/curl/archive) and the
# submodule exts (ed25519/lzfse/zstd), plus the pure-szl network exts (server/resp/http/https) that only
# add I/O surface. Keeps the always-on interpreter + core builtins + the `test` ext (for the oracle).
SZL_OPTS=(
  -Dbuiltin_all=true
  -Dwith_tls=no -Dwith_zlib=no -Dwith_ffi=no -Dwith_curl=no -Dwith_archive=no
  -Dwith_ed25519=no -Dwith_lzfse=no -Dwith_zstd=no
  -Dwith_server=no -Dwith_resp=no -Dwith_http=no -Dwith_https=no
)

# ---------------------------------------------------------------------------
# (1) TEST build — szl's OWN flags, no sanitizer. Produces the known-answer oracle binary that
#     mayhem/test.sh runs against test/test_*.szl. Built into its own dir so it coexists with the
#     sanitized build. builtin_all=true so it's a single self-contained binary (no ext .so loading).
# ---------------------------------------------------------------------------
rm -rf build-tests
CC="$CC" meson setup build-tests "${SZL_OPTS[@]}"
ninja -C build-tests src/szl
mkdir -p /mayhem/build-tests
cp -f build-tests/src/szl /mayhem/build-tests/szl

# ---------------------------------------------------------------------------
# (2) FUZZ build — the interpreter compiled WITH $SANITIZER_FLAGS so the fuzzed code is instrumented
#     (ASan+UBSan, both halting, by default). szl reference-counts and cleans up properly even on error/
#     exception paths (verified: no LeakSanitizer floods on malformed inputs), so we keep LSan ON — full
#     ASan + UBSan, all halting. szl is the file-input Mayhem target at /mayhem/szl.
#     We pass $SANITIZER_FLAGS to BOTH compile (CFLAGS) and link (LDFLAGS) so the sanitizer runtime is
#     linked into the final binary; the empty off-switch yields a clean, sanitizer-free interpreter.
# ---------------------------------------------------------------------------
rm -rf build
CC="$CC" CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" LDFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" meson setup build "${SZL_OPTS[@]}"
ninja -C build src/szl
cp -f build/src/szl /mayhem/szl

echo "build.sh: built /mayhem/szl (sanitized fuzz target) and /mayhem/build-tests/szl (test oracle)"
ls -l /mayhem/szl /mayhem/build-tests/szl
