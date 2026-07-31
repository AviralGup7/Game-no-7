#!/usr/bin/env bash
# Verify every audio asset referenced in code exists on disk, decodes, and is
# declared in pubspec. A missing asset is a runtime-only failure in Flutter —
# it will not show up in `flutter analyze`, only as silence or an exception on
# a user's device. So we check it in CI instead.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0

echo "== 1. assets referenced in Dart exist on disk"
refs=$(grep -rhoP "(?<=')(sfx|music)/[a-z0-9_]+\.ogg(?=')" lib/ | sort -u)
[ -z "$refs" ] && { echo "  ! no asset references found - did the enum move?"; fail=1; }
for r in $refs; do
  if [ -f "assets/audio/$r" ]; then echo "  ok   $r"
  else echo "  FAIL $r  (referenced in code, missing on disk)"; fail=1; fi
done

echo "== 2. files on disk decode cleanly"
if command -v ffprobe >/dev/null 2>&1; then
  while IFS= read -r f; do
    if ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" >/dev/null 2>&1; then
      d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")
      printf "  ok   %-42s %ss\n" "${f#assets/audio/}" "${d%.*}"
    else echo "  FAIL $f does not decode"; fail=1; fi
  done < <(find assets/audio -name '*.ogg' | sort)
else echo "  (ffprobe absent - skipping decode check)"; fi

echo "== 2b. SFX are audible (>=30ms) and music is long enough to loop (>=30s)"
if command -v ffprobe >/dev/null 2>&1; then
  while IFS= read -r f; do
    d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")
    ms=$(awk "BEGIN{printf \"%d\", $d*1000}")
    case "$f" in
      */sfx/*) min=30;   what="sfx" ;;
      */music/*) min=30000; what="music" ;;
      *) min=0; what="?" ;;
    esac
    if [ "$ms" -ge "$min" ]; then printf "  ok   %-42s %sms\n" "${f#assets/audio/}" "$ms"
    else echo "  FAIL ${f#assets/audio/} is ${ms}ms - too short for $what (min ${min}ms)"; fail=1; fi
  done < <(find assets/audio -name '*.ogg' | sort)
fi

echo "== 3. pubspec declares the asset folders"
for d in "assets/audio/music/" "assets/audio/sfx/"; do
  if grep -q "$d" pubspec.yaml; then echo "  ok   $d declared"
  else echo "  FAIL $d not in pubspec.yaml"; fail=1; fi
done

echo "== 4. every shipped asset is attributed"
while IFS= read -r f; do
  b=$(basename "$f")
  if grep -q "$b" ATTRIBUTION.md; then echo "  ok   $b"
  else echo "  FAIL $b missing from ATTRIBUTION.md"; fail=1; fi
done < <(find assets/audio -name '*.ogg' | sort)

echo "== 5. size budget"
tot=$(du -sk assets/audio | cut -f1)
echo "  audio total: ${tot} KB"
if [ "$tot" -gt 6144 ]; then echo "  FAIL over 6 MB budget"; fail=1; else echo "  ok   within 6 MB budget"; fi

echo
if [ "$fail" -eq 0 ]; then echo "ASSET VERIFICATION PASSED"; else echo "ASSET VERIFICATION FAILED"; fi
exit $fail
