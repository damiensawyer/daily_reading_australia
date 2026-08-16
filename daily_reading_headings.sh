#!/bin/bash
curl -s "https://universalis.com/Australia/jsonpmass.js" \
  | sed -E 's/^universalisCallback\((.*)\);?$/\1/' \
  | jq -r '
    "=== " + (.day // "Today") + " (" + (.date // "") + ") ===\n" +
    "First Reading:      " + (.Mass_R1.source // "N/A") + "\n" +
    "Responsorial Psalm: " + (.Mass_Ps.source // "N/A") + "\n" +
    (if .Mass_R2.source then "Second Reading:     " + .Mass_R2.source + "\n" else "" end) +
    "Gospel:             " + (.Mass_G.source // "N/A")
  '

