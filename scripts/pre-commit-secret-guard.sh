#!/usr/bin/env bash
#
# Pre-commit secret guard for the MTX Route Checklist (PUBLIC repo).
#
# Blocks a commit if a staged, tracked file looks like it contains a real
# door / apartment / wifi / med-lock / thermostat CODE. Those secrets belong
# ONLY in route-checklist/house-codes.local.js (gitignored, on-device) — never
# in house-data.js, the SQL migrations, or anything else that gets pushed.
#
# It is deliberately NARROW: it matches secret-bearing LABELS next to digits,
# not "any number", so furnace-filter sizes (16x25x4), dates (7/2028), and
# quantities don't trip it. False alarms train people to ignore guards.
#
# To bypass in a genuine false-positive:  git commit --no-verify
# (Use that sparingly and only when you're certain the match is not a secret.)

set -u

# The one file allowed to hold real codes is gitignored, so it never reaches
# staging — no allowlist needed. We only scan what's actually staged.

# Label patterns that indicate a real secret. Case-insensitive.
#
# Two data shapes carry codes in this project:
#   object: medLock: "Brand NNNN"
#   array : ["Garage code", "NNNN"]
# In the array shape the label is followed by `", "` before the value, so the
# gap between a label and its code can contain quotes and commas. Each pattern
# below therefore allows any chars (.*) between the label and a quoted value,
# then requires that value to contain a CODE — a run of 3+ digits (a real combo
# / PIN), or an alphanumeric wifi-style password. This matches both shapes and
# does not depend on how many quotes sit between label and value.
#
# It stays narrow by requiring a 3+ char code inside quotes, so incidental
# digits ("16x25x4", "1 keypad", a date "7/2028") do not trip it.
# A "code value" is a quoted string containing either a run of 2+ digits
# (4079, 007) OR a separated digit sequence — digits joined by spaces, dashes,
# commas, or plus signs (5-3-1, 5 4 1, "1, 3, 5", "2+4 then 3", 01 03 17).
# CODE holds that fragment once so every label pattern uses the same shape.
# (2026-07-10: broadened after "01 03 17", a real shed combination, slipped
# through, and comma/plus press-sequences were found unmatched in testing.)
CODE='([0-9]{2,}|[0-9]([ ,+-]+[0-9]){1,})'
patterns=(
  'garage code.*"[^"]*'"$CODE"
  'apt\.? code.*"[^"]*'"$CODE"
  'apartment code.*"[^"]*'"$CODE"
  'apt code.*"[^"]*'"$CODE"
  'apt key.*"[^"]*[0-9]{3,}'
  'side door code.*"[^"]*'"$CODE"
  'door code.*"[^"]*'"$CODE"
  'wifi password.*"[^"]*[0-9a-z]{4,}'
  'thermostat.*combo.*"[^"]*'"$CODE"
  # Med lock / lock-brand lines: only a secret when a 3+ digit combo appears in
  # quotes. "Stealth lock (code in local codes file)" and "1 keypad" are fine;
  # "Stelth 2256" / "Digi Lock-C 1256" are not.
  'med.?lock.*"[^"]*[0-9]{3,}'
  'digi ?lock.*[^0-9][0-9]{3,}'
  'ste[al]*lth[^"]*[0-9]{3,}'
  # Labels added 2026-07-10 (see CODE note above). Unlike the labels higher up,
  # these words also appear in INNOCENT tracked lines ("Shed","Yes (no lock
  # needed)"), so they anchor tighter: the code must sit inside the label's own
  # quoted value — `label…", "value-containing-code"` — not merely later on the
  # same line (long one-line JSON in the SQL has dates in later fields).
  # "Combination in local codes file" / "House code: None" have no digits — pass.
  'shed[^"]*" *, *"[^"]*'"$CODE"
  'house code[^"]*" *, *"[^"]*'"$CODE"
  'basement (code|access)[^"]*" *, *"[^"]*'"$CODE"
  'office code[^"]*" *, *"[^"]*'"$CODE"
  'downstairs code[^"]*" *, *"[^"]*'"$CODE"
  'keyless entry[^"]*" *, *"[^"]*[0-9]{3,}'
  'med(icine)? (cabinet|closet)[^"]*" *, *"[^"]*[0-9]{3,}'
  'alarm code[^"]*" *, *"[^"]*'"$CODE"
)

# Only look at files staged for commit (Added/Copied/Modified), skip deletions.
staged=$(git diff --cached --name-only --diff-filter=ACM)
[ -z "$staged" ] && exit 0

hits=""
while IFS= read -r file; do
  [ -f "$file" ] || continue
  # Skip the guard's own files — they contain the label patterns by definition,
  # so scanning them would always self-flag (they hold no real codes).
  case "$file" in
    scripts/pre-commit-secret-guard.sh|scripts/install-hooks.sh) continue ;;
  esac
  # Scan the staged content (what will actually be committed), not the worktree.
  content=$(git show ":$file" 2>/dev/null) || continue
  for pat in "${patterns[@]}"; do
    match=$(printf '%s' "$content" | grep -inE "$pat" || true)
    if [ -n "$match" ]; then
      hits="${hits}\n  ${file}:\n$(printf '%s' "$match" | sed 's/^/      /')"
    fi
  done
done <<< "$staged"

if [ -n "$hits" ]; then
  printf '\n\033[1;31mBLOCKED: a staged file looks like it contains a real access code.\033[0m\n'
  printf 'This repo is PUBLIC — door/apt/wifi/med-lock codes must live ONLY in\n'
  printf 'route-checklist/house-codes.local.js (gitignored, on-device).\n'
  printf '\nSuspicious lines:%b\n' "$hits"
  printf '\nFix: move the code into house-codes.local.js and replace it in the\n'
  printf 'tracked file with a note like "(code in local codes file)".\n'
  printf 'If this is a genuine false positive, re-run with:  git commit --no-verify\n\n'
  exit 1
fi

exit 0
