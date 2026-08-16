#!/usr/bin/env bash
# Print today's full Mass readings (Universalis, Australian lectionary).
# Output: markdown to stdout — H1 date, H2 per reading section.
#
#   ./daily_reading_text.sh            # stream markdown
#   ./daily_reading_text.sh | glow -   # render in terminal

set -euo pipefail

curl -fsSL "https://universalis.com/Australia/jsonpmass.js" \
    | sed -E 's/^universalisCallback\((.*)\);[[:space:]]*$/\1/' \
    | jq -r '
        # Decode the HTML entities Universalis uses.
        def entities:
            gsub("&#160;|&#xa0;|&nbsp;"; " ")
            | gsub("&#x2010;"; "-")
            | gsub("&#x2013;"; "\u2013")
            | gsub("&#x2018;"; "\u2018")
            | gsub("&#x2019;"; "\u2019")
            | gsub("&#x201c;"; "\u201c")
            | gsub("&#x201d;"; "\u201d")
            | gsub("&#xa9;"; "\u00a9")
            | gsub("&amp;"; "&");

        # Strip HTML tags and trim whitespace.
        def plain: (. // "") | gsub("<[^>]*>"; "") | entities | gsub("^\\s+|\\s+$"; "");

        # Convert a block of Universalis HTML into markdown paragraphs.
        # Each <div> becomes a paragraph; <i>/<b> become */** emphasis.
        def paragraphs:
            (. // "")
            | gsub("<div[^>]*>"; "\u0000")
            | gsub("</div>"; "")
            | split("\u0000")
            | map(
                  gsub("<i[^>]*>"; "*") | gsub("</i>"; "*")
                  | gsub("<b[^>]*>"; "**") | gsub("</b>"; "**")
                  | gsub("<[^>]*>"; "")
                  | entities
                  | gsub("^\\s+|\\s+$"; "")
              )
            | map(select(length > 0));

        # One reading as a markdown section: H2, bold citation, optional
        # italic heading line, then the text paragraphs.
        def section($title; $r):
            "## \($title)\n\n**\($r.source | plain)**"
            + (if ($r.heading | plain) != "" then " — *\($r.heading | plain)*" else "" end)
            + "\n\n\($r.text | paragraphs | join("\n\n"))";

        [
            "# \(.date | plain)",
            (.day | plain),
            section("First Reading"; .Mass_R1),
            section("Responsorial Psalm"; .Mass_Ps),
            (if (.Mass_R2.source // "") != "" then section("Second Reading"; .Mass_R2) else empty end),
            (if (.Mass_GA.source // "") != "" then section("Gospel Acclamation"; .Mass_GA) else empty end),
            section("Gospel"; .Mass_G),
            "---",
            "*\(.copyright.text | plain)*"
        ] | join("\n\n")
    '
