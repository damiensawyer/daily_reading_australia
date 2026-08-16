#!/usr/bin/env bash
# Generate today's Mass readings as an audio mp3 via the ElevenLabs API.
#
#   ./tts_daily_reading.sh                 # fetch today's readings -> audio/YYYY-MM-DD-<voice>.mp3
#   ./tts_daily_reading.sh --force         # regenerate even if today's file exists
#   ./tts_daily_reading.sh --print-text    # show the text that would be spoken (no API call)
#   ./tts_daily_reading.sh --list-voices   # list voices on your account
#   ./tts_daily_reading.sh --voice brian   # override voice for this run
#   ./tts_daily_reading.sh --model eleven_multilingual_v2
#
# Configuration is read (first match wins) from:
#   1. $DAILY_READING_ENV   (explicit path)
#   2. ./.env               (repo-local, gitignored)
#   3. ~/.config/daily-reading/env   (stow-friendly — see setup.sh)
#
# Depends on: curl, jq  (and text_daily_reading.sh in the same directory)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_BASE="${ELEVENLABS_API_BASE:-https://api.elevenlabs.io}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
[[ -n "${HOME:-}" ]] || die 'HOME is not set'
usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# --- Load configuration -----------------------------------------------------

load_env() {
    local f
    local candidates=(
        "${DAILY_READING_ENV:-}"
        "$SCRIPT_DIR/.env"
        "${XDG_CONFIG_HOME:-$HOME/.config}/daily-reading/env"
    )
    for f in "${candidates[@]}"; do
        [[ -z "$f" || ! -f "$f" ]] && continue
        # Only source files made of plain VAR=value lines and comments.
        if grep -qvE '^[[:space:]]*(#.*|)$|^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=.*$' "$f"; then
            die "refusing to source '$f': it contains lines that are not simple assignments"
        fi
        # shellcheck disable=SC1090
        . "$f"
        return 0
    done
}

load_env

ELEVENLABS_API_KEY="${ELEVENLABS_API_KEY:-}"
ELEVENLABS_VOICE="${ELEVENLABS_VOICE:-rachel}"
ELEVENLABS_VOICE_NAME="${ELEVENLABS_VOICE_NAME:-}"   # display name for the filename
ELEVENLABS_MODEL_ID="${ELEVENLABS_MODEL_ID:-eleven_flash_v2_5}"
ELEVENLABS_OUTPUT_FORMAT="${ELEVENLABS_OUTPUT_FORMAT:-mp3_44100_64}"
ELEVENLABS_STABILITY="${ELEVENLABS_STABILITY:-0.5}"
ELEVENLABS_SIMILARITY="${ELEVENLABS_SIMILARITY:-0.75}"
ELEVENLABS_SPEAKER_BOOST="${ELEVENLABS_SPEAKER_BOOST:-true}"
AUDIO_DIR="${AUDIO_DIR:-$SCRIPT_DIR/audio}"

# --- Arguments ---------------------------------------------------------------

FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force|-f)      FORCE=1 ;;
        --print-text)    ACTION=print-text ;;
        --list-voices)   ACTION=list-voices ;;
        --voice)         [[ $# -ge 2 ]] || die "--voice needs a value"; ELEVENLABS_VOICE="$2"; ELEVENLABS_VOICE_NAME=""; shift ;;
        --model)         [[ $# -ge 2 ]] || die "--model needs a value"; ELEVENLABS_MODEL_ID="$2"; shift ;;
        --help|-h)       usage ;;
        *)               die "unknown option: $1 (try --help)" ;;
    esac
    shift
done
ACTION="${ACTION:-speak}"

[[ "$ACTION" == "speak" && -z "$ELEVENLABS_API_KEY" ]] && \
    die "no API key configured. Run ./setup.sh (or see .env.example)"

require_key() { [[ -n "$ELEVENLABS_API_KEY" ]] || die "no API key configured. Run ./setup.sh"; }

# --- Voice resolution --------------------------------------------------------

fetch_voices() {
    curl -fsS "$API_BASE/v1/voices" -H "xi-api-key: $ELEVENLABS_API_KEY" 2>/dev/null \
        || die "could not reach ElevenLabs or bad API key"
}

# Accept a voice name or ID; sets VOICE_ID and VOICE_NAME. The name is
# looked up when the config only has an ID (so files can be named after
# the voice) or when a name was given.
resolve_voice() {
    local v="$1" match
    if [[ "$v" =~ ^[A-Za-z0-9_-]{16,}$ ]]; then
        VOICE_ID="$v"
        VOICE_NAME="$ELEVENLABS_VOICE_NAME"
        if [[ -z "$VOICE_NAME" ]]; then
            VOICE_NAME="$(fetch_voices \
                | jq -r --arg id "$v" '.voices[] | select(.voice_id == $id) | .name')"
            [[ -n "$VOICE_NAME" ]] || VOICE_NAME="$v"
        fi
        return 0
    fi
    match="$(fetch_voices \
        | jq -er --arg name "${v,,}" \
              '.voices[] | select((.name | ascii_downcase) == $name) | "\(.voice_id)\t\(.name)"')" \
        || die "voice '$v' not found — run ./tts_daily_reading.sh --list-voices"
    VOICE_ID="${match%%$'\t'*}"
    VOICE_NAME="${match#*$'\t'}"
}

list_voices() {
    require_key
    fetch_voices \
        | jq -r '.voices[]
            | "\(.voice_id)  \(.name)  "
              + (if .labels.accent then "[\(.labels.accent)] " else "" end)
              + (if .labels.description then "— \(.labels.description)" else "" end)'
}

# --- Text preparation --------------------------------------------------------

# Today's readings as markdown, transformed into clean speech text:
#   "Readings for <date>. <feast>." intro, then each section as
#   "First Reading. <citation>" followed by the text itself.
# Dropped as noise when spoken: markdown syntax, thematic titles and
# psalm-refrain headings (the refrain is already inside the text), the
# Gospel Acclamation citation (e.g. "Mt5:3"; its text opens with
# "Alleluia, alleluia!" anyway), psalm double-numbering
# ("Psalm 66(67):..." -> "Psalm 66"), and the copyright footer.
prepare_text() {
    "$SCRIPT_DIR/text_daily_reading.sh" | awk '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        function clean(s) { gsub(/\*\*/, "", s); gsub(/\*/, "", s); return trim(s) }
        function blankline() { if (!lastblank) { print ""; lastblank = 1 } }
        function emit(s)    { print s; lastblank = 0 }
        function flushbuf() { if (buf != "") { emit(buf); buf = "" } }

        # H1 date line: remember it, wait for the feast/day line.
        /^# / { date = clean(substr($0, 3)); state = "day"; next }

        state == "day" {
            if (trim($0) == "") next
            emit("Readings for " date ". " clean($0) ".")
            state = "text"
            next
        }

        # Section heading: spoken as a one-line lead-in.
        /^## / {
            flushbuf()
            sec = trim(substr($0, 4))
            blankline()
            emit(sec ".")
            state = "cite"
            next
        }

        # Horizontal rule: everything after is the copyright footer.
        /^---/ { exit }

        # Citation line: "**Isaiah 56:1,6-7** — *title*". Keep the
        # citation (simplified), drop the thematic title. The Gospel
        # Acclamation citation ("Mt5:3" etc.) reads as noise — skip it.
        state == "cite" && trim($0) != "" {
            if ($0 !~ /^[ \t]*\*\*/) { state = "text" }   # no citation; text follows
            else {
                cite = $0
                sub(/^[ \t]*\*\*/, "", cite)
                sub(/\*\*.*/, "", cite)                 # drops " — *title*" too
                cite = trim(cite)
                if (cite ~ /^Psalm [0-9]+\(/) sub(/\(.*/, "", cite)
                if (cite != "" && sec != "Gospel Acclamation")
                    emit(cite (cite ~ /[.!?,;:]$/ ? "" : "."))
                state = "refrain"
            }
            next
        }

        # Italic line straight after the citation = refrain/title heading;
        # it repeats inside the text, so skip it. Otherwise: text starts.
        state == "refrain" && trim($0) != "" {
            if ($0 ~ /^[ \t]*\*/) { state = "text"; next }
            state = "text"              # fall through to the text rule
        }

        # A blank line marks a *pending* paragraph break — we honour it
        # only if the sentence has actually ended (see text rule).
        /^$/ { if (state == "text") pend = 1; next }

        # Verse lines are split one-per-paragraph in the source; join them
        # into flowing sentences, breaking only where the sentence ends.
        state == "text" {
            line = clean($0)
            if (line == "") next
            if (pend) {
                if (buf ~ /[.!?:;’”]$/) { emit(buf); buf = ""; blankline() }
                pend = 0
            }
            buf = (buf == "" ? line : buf " " line)
            next
        }

        END { flushbuf() }
    '
}

case "$ACTION" in
    list-voices) list_voices; exit 0 ;;
    print-text)  prepare_text; exit 0 ;;
esac

# --- Speak --------------------------------------------------------------------

TEXT="$(prepare_text)"
[[ -n "$TEXT" ]] || die "text_daily_reading.sh produced no text"

DATE="$(date +%F)"
mkdir -p "$AUDIO_DIR"

VOICE_ID=""
VOICE_NAME=""
resolve_voice "$ELEVENLABS_VOICE"

# "Brian" -> "brian"; "Charlotte CL" -> "charlotte-cl"
VOICE_SLUG="${VOICE_NAME,,}"
VOICE_SLUG="${VOICE_SLUG// /-}"
VOICE_SLUG="${VOICE_SLUG//[^a-z0-9_-]/}"
OUT_FILE="$AUDIO_DIR/$DATE-${VOICE_SLUG:-voice}.mp3"

if [[ -e "$OUT_FILE" && "$FORCE" -eq 0 ]]; then
    printf 'already exists: %s (use --force to regenerate)\n' "$OUT_FILE"
    exit 0
fi

CHARS="$(printf '%s' "$TEXT" | wc -c | tr -d ' ')"
printf 'Generating %s\n  voice:  %s (%s)\n  model:  %s\n  format: %s\n  text:   %s chars\n' \
    "$OUT_FILE" "$VOICE_NAME" "$VOICE_ID" "$ELEVENLABS_MODEL_ID" \
    "$ELEVENLABS_OUTPUT_FORMAT" "$CHARS"

BODY="$(jq -n \
    --arg text "$TEXT" \
    --arg model "$ELEVENLABS_MODEL_ID" \
    --argjson stability "$ELEVENLABS_STABILITY" \
    --argjson similarity "$ELEVENLABS_SIMILARITY" \
    --argjson boost "$ELEVENLABS_SPEAKER_BOOST" \
    '{text: $text, model_id: $model,
      voice_settings: {stability: $stability, similarity_boost: $similarity, use_speaker_boost: $boost}}')" \
    || die "ELEVENLABS_STABILITY / SIMILARITY / SPEAKER_BOOST must be JSON numbers/booleans"

TMP="$(mktemp --suffix=.mp3)"
trap 'rm -f "$TMP"' EXIT

HTTP_CODE="$(curl -sS -o "$TMP" -w '%{http_code}' -X POST \
    "$API_BASE/v1/text-to-speech/$VOICE_ID?output_format=$ELEVENLABS_OUTPUT_FORMAT" \
    -H "xi-api-key: $ELEVENLABS_API_KEY" \
    -H 'Content-Type: application/json' \
    -d "$BODY")" || { cat "$TMP" >&2; die "request to ElevenLabs failed"; }

if [[ "$HTTP_CODE" != "200" ]]; then
    { jq -r '.detail.message // .detail // .' "$TMP" 2>/dev/null || cat "$TMP"; } >&2
    die "ElevenLabs API returned HTTP $HTTP_CODE"
fi

mv "$TMP" "$OUT_FILE"
trap - EXIT
printf 'done: %s (%s)\n' "$OUT_FILE" "$(du -h "$OUT_FILE" | cut -f1)"
