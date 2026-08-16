# Daily Reading Helpers — Australia

Small shell scripts that fetch and format today's Mass readings from
[Universalis](https://universalis.com) (Australian lectionary, Melbourne),
and read them aloud as an mp3 via the [ElevenLabs](https://elevenlabs.io) API.
Today's date is taken from the local machine's clock, so the readings
always match your local calendar day.

See also the [daily reading web page](https://universalis.com/australia.melbourne/1000/mass.htm).

## Scripts

| Script | Output |
|---|---|
| `headings_daily_reading.sh` | Plain-text list of just the reading citations for today's Mass |
| `text_daily_reading.sh` | Full readings as markdown — H1 date, H2 per reading section |
| `formatted.sh` | Runs `text_daily_reading.sh` and renders the markdown in the terminal via [glow](https://github.com/charmbracelet/glow) |
| `tts_daily_reading.sh` | Full readings as a small mp3 in `audio/`, via ElevenLabs |
| `setup.sh` | One-time setup: prompts for your ElevenLabs API key and writes your (gitignored) config |

## Usage

```sh
# Just the reading references
./headings_daily_reading.sh

# Full readings as markdown
./text_daily_reading.sh

# Full readings, rendered nicely in the terminal
./formatted.sh

# Today's readings as audio (audio/YYYY-MM-DD-<voice>.mp3)
./tts_daily_reading.sh

# Regenerate today's file, preview the spoken text, list voices
./tts_daily_reading.sh --force
./tts_daily_reading.sh --print-text
./tts_daily_reading.sh --list-voices
```

Sections without a reading (e.g. no Second Reading on weekdays) are
omitted automatically.

The spoken text is cleaned up for listening: it opens with "Readings for
<date>. <feast>.", then each section as "First Reading. <citation>" followed
by the text. Thematic titles, psalm double-numbering ("Psalm 66(67):…" →
"Psalm 66"), the Gospel Acclamation citation, and the copyright footer are
dropped. Preview exactly what gets spoken with `./tts_daily_reading.sh --print-text`.

## Text-to-speech setup (one time)

```sh
./setup.sh
```

It prompts for your ElevenLabs API key (hidden input), validates it against
the API, lists the voices on your account by number for you to pick from,
and writes your config to `~/.config/daily-reading/env` —
**outside this repo**, so your key can never be pushed to GitHub.
`.env.example` is the committed template; the real file is ignored by
`.gitignore`.

To keep the config file with your dotfiles instead (GNU stow):

```sh
# creates ~/.dotfiles/daily-reading/.config/daily-reading/env
# and symlinks ~/.config/daily-reading/env to it
DOTFILES_DIR=~/my-dotfiles ./setup.sh --stow
```

Then your key travels with your dotfiles repo (keep that repo private!)
and this repo stays clean for GitHub. You can also write a repo-local,
gitignored `./.env` with `./setup.sh --local`.

### Configuration

Config is read from the first of: `$DAILY_READING_ENV`, `./.env`,
`~/.config/daily-reading/env`. See `.env.example` for all options:

| Variable | Default | Notes |
|---|---|---|
| `ELEVENLABS_API_KEY` | — | Required, from [API keys](https://elevenlabs.io/app/settings/api-keys) |
| `ELEVENLABS_VOICE` | `rachel` | Voice ID (what `setup.sh` saves) or name (`--list-voices` to browse) |
| `ELEVENLABS_VOICE_NAME` | looked up | Display name of the voice; used for the `YYYY-MM-DD-<voice>.mp3` filename |
| `ELEVENLABS_MODEL_ID` | `eleven_flash_v2_5` | Cheap & good; `eleven_multilingual_v2` for best quality |
| `ELEVENLABS_OUTPUT_FORMAT` | `mp3_44100_64` | 64 kbps mp3 — small files, fine for speech |
| `ELEVENLABS_STABILITY` | `0.5` | Higher = steadier, lower = more expressive |
| `ELEVENLABS_SIMILARITY` | `0.75` | How closely to stick to the original voice |
| `AUDIO_DIR` | `./audio` | Where mp3s land |

A day's readings are roughly 3,000–5,000 characters, so on the flash model
this costs a few hundred credits per day.

## Running daily

cron:

```cron
30 6 * * *  /home/you/code/daily_reading/tts_daily_reading.sh >> /tmp/daily-reading-tts.log 2>&1
```

or a systemd user timer:

```ini
# ~/.config/systemd/user/daily-reading-tts.timer
[Unit]
Description=Daily readings text-to-speech

[Timer]
OnCalendar=*-*-* 06:30:00
Persistent=true

[Install]
WantedBy=timers.target
```

```ini
# ~/.config/systemd/user/daily-reading-tts.service
[Unit]
Description=Daily readings text-to-speech

[Service]
Type=oneshot
ExecStart=/home/you/code/daily_reading/tts_daily_reading.sh
```

Enable with `systemctl --user enable --now daily-reading-tts.timer`.

## Dependencies

- `curl`
- `jq`
- `glow` (only for `formatted.sh`)
- GNU `stow` (only for `setup.sh --stow`)
