#!/usr/bin/env bash
# Read today's Mass readings aloud with Kokoro TTS (koko), locally — no API.
#
#   ./drr.sh            # play today's readings (generates mp3/YYYYMMDD.mp3 first if needed)
#   ./drr.sh --force    # regenerate today's mp3 even if it exists
#   ./drr.sh --no-play  # just make the mp3
#   ./drr.sh --print-text   # show the text that would be spoken
#
# Env: KOKO_STYLE (default bm_george), KOKO_SPEED (default 0.85),
#      KOKO_MODEL, KOKO_DATA
#
# Text comes from `tts_daily_reading.sh --print-text`, then HTML entities are
# decoded and numbers are spoken as words ("Luke 21:5-11" -> "Luke chapter
# twenty-one, verses five to eleven").

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL="${KOKO_MODEL:-$HOME/.local/share/kokoro/kokoro-v1.0.onnx}"
DATA="${KOKO_DATA:-$HOME/.local/share/kokoro/voices-v1.0.bin}"
STYLE="${KOKO_STYLE:-bm_george}"
SPEED="${KOKO_SPEED:-0.85}"
MP3_DIR="$SCRIPT_DIR/mp3"
MP3="$MP3_DIR/$(date +%Y%m%d).mp3"

FORCE=0 PLAY=1 PRINT=0
for a in "$@"; do
    case "$a" in
        --force|-f)   FORCE=1 ;;
        --no-play)    PLAY=0 ;;
        --print-text) PRINT=1 ;;
        --help|-h)    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)            echo "unknown option: $a (try --help)" >&2; exit 1 ;;
    esac
done

speech_text() {
    "$SCRIPT_DIR/tts_daily_reading.sh" --print-text | python3 -c '
import html, re, sys

ONES = ("zero one two three four five six seven eight nine ten eleven twelve thirteen "
        "fourteen fifteen sixteen seventeen eighteen nineteen").split()
TENS = "_ _ twenty thirty forty fifty sixty seventy eighty ninety".split()
ORD = {"one": "first", "two": "second", "three": "third", "five": "fifth", "eight": "eighth",
       "nine": "ninth", "twelve": "twelfth"}

def w(n):
    n = int(n)
    if n < 20: return ONES[n]
    if n < 100: return TENS[n // 10] + ("-" + ONES[n % 10] if n % 10 else "")
    if n < 1000:
        r = n % 100
        return ONES[n // 100] + " hundred" + (" and " + w(r) if r else "")
    if n < 1000000:
        r = n % 1000
        return w(n // 1000) + " thousand" + ((" and " if r < 100 else " ") + w(r) if r else "")
    return str(n)

def ordinal(n):
    words = w(n)
    head, sep, last = words.rpartition("-") if "-" in words else ("", "", words)
    last = ORD.get(last) or (last[:-1] + "ieth" if last.endswith("y") else last + "th")
    return head + sep + last

def verses(spec):
    spec = re.sub(r"(?<=\d)[a-z]+", "", spec)            # 11a -> 11
    parts = [p for p in spec.split(",") if p]
    spoken = [" to ".join(w(x) for x in re.split(r"[-–]", p) if x) for p in parts]
    plural = len(parts) > 1 or re.search(r"[-–]", spec)
    return ("verses " if plural else "verse ") + ", ".join(spoken)

MONTHS = "January|February|March|April|May|June|July|August|September|October|November|December"

text = html.unescape(sys.stdin.read())
# "24 November 2026" -> "the twenty-fourth of November, two thousand and twenty-six"
text = re.sub(rf"\b(\d{{1,2}}) ({MONTHS}) (\d{{4}})\b",
              lambda m: f"the {ordinal(m[1])} of {m[2]}, {w(m[3])}", text)
# "week 34" -> "the thirty-fourth week"
text = re.sub(r"\bweek (\d+)\b", lambda m: f"the {ordinal(m[1])} week", text)
# "21:5-11" -> "chapter twenty-one, verses five to eleven"
text = re.sub(r"\b(\d+):([\d,\-–a-z]+)",
              lambda m: f"chapter {w(m[1])}, {verses(m[2])}", text)
# Any remaining numbers.
text = re.sub(r"\b\d+\b", lambda m: w(m[0]), text)
text = re.sub(r"  +", " ", text)
sys.stdout.write(text)
'
}

if (( PRINT )); then speech_text; exit 0; fi

if (( FORCE )) || [[ ! -s "$MP3" ]]; then
    mkdir -p "$MP3_DIR"
    text="$(speech_text)"
    [[ -n "${text//[[:space:]]/}" ]] || { echo "error: no reading text" >&2; exit 1; }
    tmp_wav="$(mktemp /tmp/drr-XXXXXX.wav)"
    trap 'rm -f "$tmp_wav"' EXIT
    echo "Generating today's readings with $STYLE at speed $SPEED (${#text} chars)…" >&2
    koko --model "$MODEL" --data "$DATA" --lan en --style "$STYLE" --speed "$SPEED" \
         text "$text" -o "$tmp_wav" >/dev/null 2>&1
    lame --quiet -V 4 "$tmp_wav" "$MP3"
    echo "✓ Saved $MP3" >&2
fi

if (( PLAY )); then
    mpv --no-video --really-quiet --term-osd-bar "$MP3"
fi
