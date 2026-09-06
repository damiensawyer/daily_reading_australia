#!/usr/bin/env bash
set -euo pipefail

# The universalis.com JSONP payload is JavaScript, not plain JSON: some string
# values carry obfuscation like "...BnD...".split("D").join("d ")... which must be
# evaluated to produce valid JSON, so use node to unwrap the callback.
curl -fsSL "https://universalis.com/Australia/$(date +%Y%m%d)/jsonpmass.js" \
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
