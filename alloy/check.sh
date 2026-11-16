#!/usr/bin/env bash
# Copyright (C) 2026 HCALC contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Expectation-checked Alloy suite for HCALC.
# Adapted from github.com/SNAPKITTYWEST/tlm-jxcl-forge alloy/invariants/check.sh
# @ commit 48891c426c4b4d61034ec1329b912e083ee7f6d8 (same owner).
#
# Every command in HCALC.als must (a) appear in alloy/expectations.tsv, (b) carry the same `expect N`
# annotation in HCALC.als, and (c) produce that result: expect 0 = UNSAT (check holds / no instance),
# expect 1 = SAT (run has an instance). Commands run one at a time (-c NAME), each writing Alloy's
# solution files to logs/check-out/NAME and its stdout to logs/check-stdout/NAME.txt (outside -o).
# A command with no SAT/UNSAT result counts as a failure. Summary goes to logs/alloy-check.txt.
# Usage: alloy/check.sh        (JAVA / ALLOY_JAR may be overridden via env)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
JAR="${ALLOY_JAR:-$ROOT/tools/org.alloytools.alloy.dist.jar}"
JAVA="${JAVA:-$(command -v java || echo "$HOME/bin/java")}"
ALS="$ROOT/HCALC.als"
EXP="$ROOT/expectations.tsv"
OUTD="$ROOT/logs/check-out"; STDD="$ROOT/logs/check-stdout"; LOG="$ROOT/logs/alloy-check.txt"
mkdir -p "$OUTD" "$STDD"
fail=0; ok=0
{
  echo "=== HCALC Alloy expectation check $(date '+%Y-%m-%dT%H:%M:%S%z') ==="
  echo "als: $ALS"; echo "expectations: $EXP"; echo -n "alloy: "; "$JAVA" -jar "$JAR" version 2>/dev/null | head -1
  # (a)+(b): command list and annotations must agree with expectations.tsv
  mapfile -t declared < <("$JAVA" -jar "$JAR" commands "$ALS" 2>/dev/null \
      | sed -nE 's/^\s*[0-9]+\s*\.\s+(Check|Run)\s+([A-Za-z0-9_]+)\s.*expect ([01]).*$/\2\t\L\1\E\t\3/p; s/^\s*[0-9]+\s*\.\s+(Check|Run)\s+([A-Za-z0-9_]+)\s.*$/\2\t\L\1\E\tMISSING/p')
  total=$("$JAVA" -jar "$JAR" commands "$ALS" 2>/dev/null | grep -cE '^\s*[0-9]+\s*\.\s+(Check|Run)\s')
  [ "$total" -eq "${#declared[@]}" ] || { echo "FAIL parsed ${#declared[@]} of $total commands"; fail=$((fail+1)); }
  mapfile -t expected < <(grep -vE '^\s*(#|$)' "$EXP")
  if [ "$(printf '%s\n' "${declared[@]}" | sort)" != "$(printf '%s\n' "${expected[@]}" | sort)" ]; then
    echo "FAIL expectations.tsv does not match the commands/annotations in HCALC.als:"
    diff <(printf '%s\n' "${expected[@]}" | sort) <(printf '%s\n' "${declared[@]}" | sort) | sed 's/^/  /'
    fail=$((fail+1))
  fi
  echo "commands: ${#expected[@]}"; echo
  # (c): run each command sequentially
  for line in "${expected[@]}"; do
    IFS=$'\t' read -r name kind want <<<"$line"
    rm -rf "$OUTD/$name"
    start=$(date +%s)
    nice -n 19 "$JAVA" -jar "$JAR" exec -f -o "$OUTD/$name" -t text -c "$name" "$ALS" > "$STDD/$name.txt" 2>&1
    rc=$?
    res=$(tr '\b' ' ' < "$STDD/$name.txt" | grep -E "^ *[0-9]+ *\. +$kind +$name " | grep -oE '\b(UNSAT|SAT)\b' | tail -1)
    case "$res" in UNSAT) got=0 ;; SAT) got=1 ;; *) got="none(rc=$rc)" ;; esac
    secs=$(( $(date +%s) - start ))
    if [ "$got" = "$want" ]; then
      printf 'ok   %-5s %-46s expect %s got %-5s (%ss)\n' "$kind" "$name" "$want" "$res" "$secs"; ok=$((ok+1))
    else
      printf 'FAIL %-5s %-46s expect %s got %s (%ss)\n' "$kind" "$name" "$want" "${res:-$got}" "$secs"; fail=$((fail+1))
    fi
  done
  echo
  echo "=== summary: ok=$ok fail=$fail ==="
} 2>&1 | tee "$LOG"
grep -q "=== summary: ok=[0-9]* fail=0 ===" "$LOG"
