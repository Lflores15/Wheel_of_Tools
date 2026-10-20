#!/bin/bash
# Headless test of every converter and tool. Usage: scripts/test_core.sh [work-dir]
set -u
cd "$(dirname "$0")/.."
swift build -q 2>&1 | grep -E "error" && exit 1
CLI=.build/debug/wot-cli
W="${1:-$(mktemp -d)}"; rm -rf "$W"; mkdir -p "$W"; cd "$W" || exit 1
pass=0; fail=0
check() { # name, command...
  local name="$1"; shift
  local out; out=$("$@" 2>&1); local rc=$?
  local ok=1 line
  # convert and file-producing tools print one output path per line: each must exist and be non-empty
  if [ "$1" = "$CLI" ] && { [ "$2" = convert ] || { [ "$2" = tool ] && [[ "$3" != metadata && "$3" != qr ]]; }; }; then
    [ -z "$out" ] && ok=0
    while IFS= read -r line; do [ -n "$line" ] && [ ! -s "$line" ] && ok=0; done <<< "$out"
  fi
  if [ $rc -eq 0 ] && [ $ok -eq 1 ]; then pass=$((pass+1)); echo "PASS $name"
  else fail=$((fail+1)); echo "FAIL $name: $out"; fi
}
# fixtures
magick -size 600x400 gradient:red-blue photo.jpg
magick -size 300x300 xc:none -fill green -draw "circle 150,150 150,20" alpha.png
magick photo.jpg photo.heic
magick -size 200x200 xc:white -fill black -draw "rectangle 20,20 180,180" qr_stub.png
qrencode -o qr.png "https://example.com" 2>/dev/null || true
printf 'Hello world\n%.0s' {1..300} > note.txt
printf '# Title\n\nSome *markdown* text.\n' > doc.md
magick photo.jpg alpha.png -density 72 two.pdf
ffmpeg -loglevel error -f lavfi -i testsrc=duration=2:size=320x240:rate=15 -f lavfi -i sine=duration=2 -shortest clip.mp4
ffmpeg -loglevel error -f lavfi -i sine=duration=2 tone.wav
printf '1\n00:00:00,000 --> 00:00:01,000\nhi\n' > sub.srt

CLI="$OLDPWD/$CLI"
for f in photo.jpg alpha.png photo.heic; do
  for ext in $($CLI formats $f); do check "$f -> $ext" $CLI convert $f $ext; done
done
$CLI convert note.txt pdf >/dev/null; for ext in $($CLI formats two.pdf | tr " " "\n" | grep -v txt); do check "two.pdf -> $ext" $CLI convert two.pdf $ext; done
for ext in $($CLI formats clip.mp4); do check "clip.mp4 -> $ext" $CLI convert clip.mp4 $ext; done
for ext in $($CLI formats tone.wav); do check "tone.wav -> $ext" $CLI convert tone.wav $ext; done
for ext in $($CLI formats note.txt); do check "note.txt -> $ext" $CLI convert note.txt $ext; done
for ext in $($CLI formats doc.md); do check "doc.md -> $ext" $CLI convert doc.md $ext; done
for ext in $($CLI formats sub.srt); do check "sub.srt -> $ext" $CLI convert sub.srt $ext; done
check "pdf text -> txt" $CLI convert note.pdf txt
check "zip -> tar" $CLI convert sub.zip tar
check "ogg compress" $CLI tool compress tone.ogg
# tools
for t in compress stripMetadata metadata qr; do check "photo.jpg $t" $CLI tool $t photo.jpg; done
check "alpha.png compress" $CLI tool compress alpha.png
check "heic compress" $CLI tool compress photo.heic
check "merge" $CLI tool merge photo.jpg two.pdf alpha.png
check "split" $CLI tool split two.pdf
check "pdf compress" $CLI tool compress two.pdf
check "pdf strip" $CLI tool stripMetadata two.pdf
check "pdf metadata" $CLI tool metadata two.pdf
check "video compress" $CLI tool compress clip.mp4
check "video snapshot" $CLI tool snapshot clip.mp4
check "video strip" $CLI tool stripMetadata clip.mp4
check "audio compress" $CLI tool compress tone.wav
check "audio normalize" $CLI tool normalize tone.wav
check "audio strip" $CLI tool stripMetadata tone.wav
# office (needs Pages / Numbers / Keynote; first run asks for Automation permission)
textutil -convert docx note.txt -output memo.docx; printf 'name,qty\napple,3\n' > data.csv
osascript -e 'tell application "Keynote"
 set d to make new document
 save d in POSIX file "'$W'/deck.key"
 close d saving no
end tell' >/dev/null 2>&1
for f in memo.docx data.csv deck.key; do for ext in $($CLI formats $f); do check "$f -> $ext" $CLI convert $f $ext; done; done
check "pptx -> pdf" $CLI convert deck.pptx pdf
check "xlsx -> csv" $CLI convert data.xlsx csv
# security regressions
printf 'push graphic-context\nviewbox 0 0 10 10\nfill red\nrectangle 0,0 10,10\npop graphic-context\n' > evil.jpg
if $CLI convert evil.jpg png >/dev/null 2>&1; then fail=$((fail+1)); echo "FAIL security: MVG disguised as .jpg was rendered"; else pass=$((pass+1)); echo "PASS security: disguised MVG rejected"; fi
printf 'x' > ./-rf; check "security: dash-named file -> tar" $CLI convert ./-rf tar
echo "--- verify formats"
for f in photo.webp photo.avif photo.tiff photo.bmp photo.gif photo.png photo.pdf photo.heic; do [ -e $f ] && magick identify -format "$f %m %wx%h\n" $f[0] 2>&1 | head -1; done
file clip.mov clip.webm clip.mkv tone.opus tone.flac note.pdf note.docx 2>&1 | head -20
echo "--- editor self-test"
WOT_SELFTEST="$W/editor" "$OLDPWD/.build/debug/WheelOfTools" || fail=$((fail+1))
echo "pass=$pass fail=$fail  dir=$W"
[ $fail -eq 0 ]
