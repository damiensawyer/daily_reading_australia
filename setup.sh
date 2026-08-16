#!/usr/bin/env bash
# One-time setup for the daily-readings text-to-speech script.
#
# Prompts for your ElevenLabs API key (hidden input), validates it against
# the API, then writes an env file. Your key NEVER lands inside this repo.
#
#   ./setup.sh            # write to ~/.config/daily-reading/env
#   ./setup.sh --stow     # write into ~/.dotfiles/daily-reading/.config/daily-reading/env
#                         # and stow it, so ~/.config/daily-reading/env is a symlink
#                         # that follows you across machines via your dotfiles repo
#   ./setup.sh --local    # write ./.env inside this repo (gitignored — still safe)
#
# The stow layout (the "extra points" layout) is:
#
#   ~/.dotfiles/daily-reading/.config/daily-reading/env   <- real file, private repo
#   ~/.config/daily-reading/env                           <- symlink created by stow
#
# Override the dotfiles location with DOTFILES_DIR=~/my-dotfiles ./setup.sh --stow
#
# Re-running is friendly: anything already in your config is offered as the
# default (just hit Enter to keep it), and the voice picker lists the voices
# on your account by number so you can pick one by typing a number.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_BASE="${ELEVENLABS_API_BASE:-https://api.elevenlabs.io}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/daily-reading"
ENV_NAME="env"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
STOW_PACKAGE="daily-reading"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
[[ -n "${HOME:-}" ]] || die 'HOME is not set'
usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

MODE="config"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --stow)   MODE="stow" ;;
        --local)  MODE="local" ;;
        --help|-h) usage ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

# --- Load existing config (if any) ---------------------------------------------

# Same candidate order as tts_daily_reading.sh.
EXISTING_FILE=""
for f in "${DAILY_READING_ENV:-}" "$SCRIPT_DIR/.env" "$CONFIG_DIR/$ENV_NAME"; do
    [[ -z "$f" || ! -f "$f" ]] && continue
    grep -qvE '^[[:space:]]*(#.*|)$|^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=.*$' "$f" && continue
    # shellcheck disable=SC1090
    . "$f"
    EXISTING_FILE="$f"
    break
done

CUR_KEY="${ELEVENLABS_API_KEY:-}"
CUR_VOICE="${ELEVENLABS_VOICE:-}"
CUR_VOICE_NAME="${ELEVENLABS_VOICE_NAME:-}"
CUR_MODEL="${ELEVENLABS_MODEL_ID:-eleven_flash_v2_5}"
CUR_FORMAT="${ELEVENLABS_OUTPUT_FORMAT:-mp3_44100_64}"

# --- API key --------------------------------------------------------------------

mask_key() { # show enough to recognise, never the whole key
    local k="$1"
    if (( ${#k} <= 10 )); then
        printf '%s****' "${k:0:2}"
    else
        printf '%s...%s' "${k:0:6}" "${k: -4}"
    fi
}

printf 'ElevenLabs setup for daily readings\n'
printf 'Get an API key at https://elevenlabs.io/app/settings/api-keys\n\n'

API_KEY=""
KEEP_KEY="$CUR_KEY"
for attempt in 1 2 3; do
    [[ $attempt -gt 1 ]] && printf '(attempt %d of 3)\n' "$attempt"
    if [[ -n "$KEEP_KEY" ]]; then
        printf 'API key [Enter = keep %s]: ' "$(mask_key "$KEEP_KEY")"
    else
        printf 'API key: '
    fi
    IFS= read -rs API_KEY
    printf '\n'
    if [[ -z "$API_KEY" && -n "$KEEP_KEY" ]]; then
        API_KEY="$KEEP_KEY"
    fi
    [[ -n "$API_KEY" ]] || { printf 'empty key, try again\n'; continue; }

    SUB="$(curl -fsS -m 20 "$API_BASE/v1/user/subscription" \
              -H "xi-api-key: $API_KEY" 2>/dev/null)" \
        || { printf 'that key was rejected by ElevenLabs — check it and try again\n'; KEEP_KEY=""; API_KEY=""; continue; }

    jq -r '"Key works: \(.tier) tier, \(.character_count)/\(.character_limit) characters used this month."' \
        <<<"$SUB" 2>/dev/null \
        || printf 'Key works (could not parse subscription details).\n'
    break
done
[[ -n "$API_KEY" ]] || die "no valid API key entered — nothing written"

# --- Voice picker ---------------------------------------------------------------

printf '\nFetching the voices on your account...\n'
VOICES_JSON="$(curl -fsS -m 20 "$API_BASE/v1/voices" -H "xi-api-key: $API_KEY" 2>/dev/null)" \
    || die "could not list voices on your account"

mapfile -t V_ID   < <(jq -r '.voices[].voice_id' <<<"$VOICES_JSON")
mapfile -t V_NAME < <(jq -r '.voices[].name' <<<"$VOICES_JSON")
mapfile -t V_DESC < <(jq -r '.voices[]
    | (if .labels.accent then "[\(.labels.accent)] " else "" end)
      + (if .labels.description then "— \(.labels.description)" else "" end)' <<<"$VOICES_JSON")
(( ${#V_ID[@]} > 0 )) || die 'no voices found on your account'

# Which entry is the current config voice (by ID, or by name)?
DEF_IDX=""
for i in "${!V_ID[@]}"; do
    if [[ -n "$CUR_VOICE" && "${V_ID[$i]}" == "$CUR_VOICE" ]]; then DEF_IDX=$((i+1)); break; fi
    if [[ -n "$CUR_VOICE" && "${V_NAME[$i],,}" == "${CUR_VOICE,,}" ]]; then DEF_IDX=$((i+1)); break; fi
    if [[ -n "$CUR_VOICE_NAME" && "${V_NAME[$i],,}" == "${CUR_VOICE_NAME,,}" ]]; then DEF_IDX=$((i+1)); break; fi
done

printf 'Voices on your account:\n'
for i in "${!V_ID[@]}"; do
    printf '  %2d. %s' "$((i+1))" "${V_NAME[$i]}"
    [[ -n "${V_DESC[$i]}" ]] && printf '  %s' "${V_DESC[$i]}"
    [[ $((i+1)) -eq "${DEF_IDX:-0}" ]] && printf '   <- current'
    printf '\n'
done

VOICE_ID="" VOICE_NAME=""
while :; do
    if [[ -n "$DEF_IDX" ]]; then
        printf 'Pick a voice by number [Enter = %d (%s)]: ' "$DEF_IDX" "${V_NAME[$((DEF_IDX-1))]}"
    else
        printf 'Pick a voice by number [1-%d]: ' "${#V_ID[@]}"
    fi
    IFS= read -r PICK
    PICK="${PICK//[[:space:]]/}"
    [[ -z "$PICK" && -n "$DEF_IDX" ]] && PICK="$DEF_IDX"

    if [[ "$PICK" =~ ^[0-9]+$ ]] && (( PICK >= 1 && PICK <= ${#V_ID[@]} )); then
        VOICE_ID="${V_ID[$((PICK-1))]}"; VOICE_NAME="${V_NAME[$((PICK-1))]}"; break
    fi
    # Also accept a typed name or a pasted voice ID.
    for i in "${!V_ID[@]}"; do
        if [[ "${V_NAME[$i],,}" == "${PICK,,}" || "${V_ID[$i]}" == "$PICK" ]]; then
            VOICE_ID="${V_ID[$i]}"; VOICE_NAME="${V_NAME[$i]}"; break
        fi
    done
    [[ -n "$VOICE_ID" ]] && break
    printf 'enter a number between 1 and %d\n' "${#V_ID[@]}"
done

# --- Model & format (Enter keeps the prefilled value) ----------------------------

printf '\nModel — eleven_flash_v2_5 (cheap/fast) or eleven_multilingual_v2 (best)\n'
IFS= read -e -i "$CUR_MODEL" -r MODEL
MODEL="${MODEL:-$CUR_MODEL}"

printf 'MP3 format (codec_samplerate_bitrate)\n'
IFS= read -e -i "$CUR_FORMAT" -r FORMAT
FORMAT="${FORMAT:-$CUR_FORMAT}"

CONTENT="$(printf "# Generated by ./setup.sh — do not commit this file.\n\
# Regenerate any time: ./setup.sh\n\
ELEVENLABS_API_KEY='%s'\n\
ELEVENLABS_VOICE='%s'\n\
# Human-readable name of ELEVENLABS_VOICE — used to name the output mp3.\n\
ELEVENLABS_VOICE_NAME='%s'\n\
ELEVENLABS_MODEL_ID='%s'\n\
ELEVENLABS_OUTPUT_FORMAT='%s'\n" \
    "${API_KEY//\'/\'\\\'\'}" "${VOICE_ID//\'/\'\\\'\'}" "${VOICE_NAME//\'/\'\\\'\'}" \
    "${MODEL//\'/\'\\\'\'}" "${FORMAT//\'/\'\\\'\'}")"

write_env() { # $1 = file
    mkdir -p "$(dirname "$1")"
    printf '%s\n' "$CONTENT" > "$1"
    chmod 600 "$1"
    printf 'wrote %s (mode 600)\n' "$1"
}

# --- Decide where the env file lives --------------------------------------------

case "$MODE" in
    local)
        write_env "$SCRIPT_DIR/.env"
        printf '(this file is gitignored — verify with: git check-ignore -v .env)\n'
        ;;
    config)
        if [[ -L "$CONFIG_DIR" ]]; then
            # Already stowed — write through the symlink into the dotfiles repo.
            write_env "$CONFIG_DIR/$ENV_NAME"
            printf '(~/.config/daily-reading is a symlink, so your key lives in your dotfiles)\n'
        else
            write_env "$CONFIG_DIR/$ENV_NAME"
            printf '\nTip: to keep this file in your dotfiles, remove %s and run:\n' "$CONFIG_DIR"
            printf '    DOTFILES_DIR=%s ./setup.sh --stow\n' "$DOTFILES_DIR"
        fi
        ;;
    stow)
        command -v stow >/dev/null || die "GNU stow not found — install it (pacman -S stow) or use plain ./setup.sh"
        [[ -d "$DOTFILES_DIR" ]] || die "$DOTFILES_DIR does not exist (set DOTFILES_DIR=... to override)"
        if [[ -d "$CONFIG_DIR" && ! -L "$CONFIG_DIR" ]]; then
            die "$CONFIG_DIR already exists as a real directory. Remove it first (rm -r), then re-run."
        fi
        REL=".config${CONFIG_DIR#$HOME/.config}"   # e.g. .config/daily-reading
        write_env "$DOTFILES_DIR/$STOW_PACKAGE/$REL/$ENV_NAME"
        ( cd "$HOME" && stow -d "$DOTFILES_DIR" -t "$HOME" "$STOW_PACKAGE" )
        printf 'stowed: %s -> %s/%s/%s\n' "$CONFIG_DIR/$ENV_NAME" \
            "$DOTFILES_DIR/$STOW_PACKAGE" "$REL" "$ENV_NAME"
        ;;
esac

printf '\nSaved: voice %s (%s), model %s, format %s\n' \
    "$VOICE_NAME" "$VOICE_ID" "$MODEL" "$FORMAT"
printf 'All set. Try it now:\n    %s/tts_daily_reading.sh\n' "$SCRIPT_DIR"
