#!/usr/bin/env bash
set -euo pipefail

curl -fsSL "https://universalis.com/Australia/$(date +%Y%m%d)/jsonpmass.js" \
    | sed -E 's/^universalisCallback\((.*)\);[[:space:]]*$/\1/' \
    | jq -r '
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

        def plain: (. // "") | gsub("<[^>]*>"; "") | entities | gsub("^\\s+|\\s+$"; "");

        "\(.date | plain) — \(.day | plain)",
        "",
        "First Reading:       \(.Mass_R1.source | plain)",
        "Responsorial Psalm:  \(.Mass_Ps.source | plain)",
        (if (.Mass_R2.source // "") != "" then "Second Reading:      \(.Mass_R2.source | plain)" else empty end),
        (if (.Mass_GA.source // "") != "" then "Gospel Acclamation:  \(.Mass_GA.source | plain)" else empty end),
        "Gospel:              \(.Mass_G.source | plain)"
    '
