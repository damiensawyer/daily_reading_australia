# Daily Reading Helpers — Australia

Small shell scripts that fetch and format today's Mass readings from
[Universalis](https://universalis.com) (Australian lectionary, Melbourne).
Each script pulls the day's JSON feed, cleans the HTML, and prints a
readable version to stdout.

See also the [daily reading web page](https://universalis.com/australia.melbourne/1000/mass.htm).

## Scripts

| Script | Output |
|---|---|
| `headings_daily_reading.sh` | Plain-text list of just the reading citations for today's Mass |
| `text_daily_reading.sh` | Full readings as markdown — H1 date, H2 per reading section |
| `formatted.sh` | Runs `text_daily_reading.sh` and renders the markdown in the terminal via [glow](https://github.com/charmbracelet/glow) |

## Usage

```sh
# Just the reading references
./headings_daily_reading.sh

# Full readings as markdown
./text_daily_reading.sh

# Full readings, rendered nicely in the terminal
./formatted.sh

# Or pipe to your own renderer
./text_daily_reading.sh | glow -
```

Sections without a reading (e.g. no Second Reading on weekdays) are
omitted automatically.

## Dependencies

- `curl`
- `jq`
- `glow` (only for `formatted.sh`)
