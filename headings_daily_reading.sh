#!/usr/bin/env bash
set -euo pipefail

# The universalis.com JSONP payload is JavaScript, not plain JSON: some string
# values carry obfuscation like "...BnD...".split("D").join("d ")... which must be
# evaluated to produce valid JSON, so use node to unwrap the callback.
# universalis.com 403s non-browser user agents, so send a browser UA.
curl -fsSL -A "Mozilla/5.0 (X11; Linux x86_64; rv:132.0) Gecko/20100101 Firefox/132.0" \
    "https://universalis.com/Australia/$(date +%Y%m%d)/jsonpmass.js" \
    | node -e '
        let s = "";
        process.stdin.on("data", d => s += d);
        process.stdin.on("end", () => {
            const m = s.match(/^universalisCallback\((.*)\);\s*$/s);
            if (!m) { console.error("unexpected payload from universalis.com"); process.exit(1); }
            process.stdout.write(JSON.stringify(eval("(" + m[1] + ")")));
        });
    ' \
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
