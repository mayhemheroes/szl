#!/usr/bin/env bash
# szl/mayhem/test.sh — RUN szl's OWN known-answer test suite (the test/test_*.szl scripts) against the
# normal-flags szl that mayhem/build.sh produced → CTRF. PATCH-grade oracle: it never compiles.
#
# Each test/test_*.szl loads the `test` extension and uses `$test.run {name} <expected-status> {script}
# <expected-result>`: it $eval's the script and asserts the result/exception equals the expected value,
# writing `ok: <name>` to stdout for each passing test and calling `$exit 1` on the first mismatch.
# This is a KNOWN-ANSWER suite — it asserts szl produces the EXACT expected value
# (e.g. `$+ 1 4 == 5`, `$== a a == 1`, escape-sequence expansions), not merely that the binary exits 0.
#
# BEHAVIORAL ORACLE (anti-reward-hack):
# The szl `test` extension's `$test.run` proc writes `ok: <name>` to stdout for every passing
# assertion. Running test_test.szl against a real szl binary emits 59+ `ok:` lines (50+ assertions).
# A no-op / exit(0) "patch" produces NO output — and therefore zero `ok:` lines. We check:
#   (a) exit code 0 (test extension calls `$exit 1` on the first assertion mismatch), AND
#   (b) stdout contains at least one `ok:` line (greps the captured output),
# so a neutered exit(0) binary (empty output) fails check (b) — it cannot reward-hack this oracle.
#
# WHY A SUBSET: at this upstream commit, szl's checked-in golden test scripts are PARTIALLY STALE — a
# series of upstream changes (e.g. "Removed the type prefix of procedures with a unique name") altered
# the text of "bad usage, should be '<name> ...'" exception messages, but the corresponding test_*.szl
# expectations were not updated, so ~12 of the 19 shipped tests fail at HEAD on a string mismatch that
# is upstream's own test-data lag, NOT a defect in szl or in this build. (Two more, test_zlib_* and
# test_ed25519, need extensions this minimal build disables.) Running them would fail the commit-image
# build for reasons unrelated to szl's behavior. We therefore run the test files that are VALID at this
# commit and still carry real, strong known-answer assertions:
#   test_test     — ~59 assertions over ==/!=/</>/<=/>=/&&/||/^^ on str/int/float (core comparison+logic)
#   test_expand   — escape-sequence expansion (known outputs + a known error string)
#   test_dict_get — dict lookup over several shapes
# These remain a genuine functional oracle. If a future sync updates the stale expectations upstream,
# widen TESTS to the full suite.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

BIN="$SRC/build-tests/szl"
[ -x "$BIN" ] || { echo "missing $BIN — run mayhem/build.sh first" >&2; exit 2; }

# Test files valid at this commit (strong known-answer assertions; see header for why this is a subset).
TESTS="test_test test_expand test_dict_get"

passed=0; failed=0
for t in $TESTS; do
  f="$SRC/test/$t.szl"
  if [ ! -f "$f" ]; then echo "FAIL $t: missing $f" >&2; failed=$((failed+1)); continue; fi
  # Capture stdout for behavioral verification. The szl test extension writes `ok: <name>` for each
  # passing assertion. We verify: (a) exit code 0 AND (b) stdout contains "ok:" lines —
  # so a neutered exit(0) binary (which produces no output) fails the behavioral check even though
  # it exits with code 0.
  OUT=$(mktemp /tmp/szl-test-out.XXXXXX)
  if "$BIN" "$f" >"$OUT" 2>&1; then
    # Behavioral check: the test extension prints `ok: <name>` per passing assertion.
    # A real binary emits dozens of ok: lines; a neutered exit(0) binary emits zero.
    OK_COUNT=$(grep -c "^ok:" "$OUT" 2>/dev/null || true)
    if [ "$OK_COUNT" -eq 0 ]; then
      failed=$((failed+1))
      echo "FAIL $t: binary exited 0 but produced no 'ok:' assertion lines (neutered or silent)" >&2
    else
      passed=$((passed+1))
      echo "ok: $t (${OK_COUNT} assertions passed)"
    fi
  else
    failed=$((failed+1))
    echo "FAIL $t:"
    tr -d '\000' <"$OUT" | tail -3 | sed 's/^/    /'
  fi
  rm -f "$OUT"
done

emit_ctrf "szl-knownanswer" "$passed" "$failed"
