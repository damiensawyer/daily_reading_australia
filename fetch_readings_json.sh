#!/usr/bin/env bash
# Fetch today's Universalis Mass readings and emit them as plain JSON on stdout.
#
# The feed is JSONP whose string values are compressed with JavaScript
# `.split("x").join("...")` chains, e.g.
#
#     "...myA above yourA.</div>".split("A").join(" thoughts")
#
# so it is not valid JSON. Rather than eval'ing remote JavaScript, the decoder
# below parses the string literals and applies the substitutions itself.
set -euo pipefail

DATE="${1:-$(date +%Y%m%d)}"

curl -fsSL "https://universalis.com/Australia/${DATE}/jsonpmass.js" \
    | python3 -c '
import json, re, sys

src = sys.stdin.read()

m = re.search(r"universalisCallback\s*\(", src)
if not m:
    sys.exit("unexpected response: no universalisCallback(...) wrapper")
start = m.end()
end = src.rindex(")")
payload = src[start:end]

ESCAPES = {"b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t",
           "\\": "\\", "\"": "\"", "'\''": "'\''", "/": "/"}


def read_string(s, i):
    """Read the JS string literal starting at s[i] (a quote). -> (value, next_i)"""
    quote = s[i]
    i += 1
    out = []
    while True:
        c = s[i]
        if c == "\\":
            nxt = s[i + 1]
            if nxt == "u":
                out.append(chr(int(s[i + 2:i + 6], 16)))
                i += 6
            elif nxt == "x":
                out.append(chr(int(s[i + 2:i + 4], 16)))
                i += 4
            else:
                out.append(ESCAPES.get(nxt, nxt))
                i += 2
        elif c == quote:
            return "".join(out), i + 1
        else:
            out.append(c)
            i += 1


def expect(s, i, token):
    j = i
    while j < len(s) and s[j].isspace():
        j += 1
    if not s.startswith(token, j):
        return None
    return j + len(token)


out = []
i = 0
n = len(payload)
while i < n:
    c = payload[i]
    if c in "\"'"'"'":
        value, i = read_string(payload, i)
        # Apply any trailing .split("x").join("y") chain, in order.
        while True:
            j = expect(payload, i, ".split(")
            if j is None:
                break
            sep, j = read_string(payload, j)
            j = expect(payload, j, ")")
            j = expect(payload, j, ".join(")
            if j is None:
                sys.exit("unexpected .split() without .join()")
            rep, j = read_string(payload, j)
            j = expect(payload, j, ")")
            value = value.replace(sep, rep)
            i = j
        out.append(json.dumps(value))
    else:
        out.append(c)
        i += 1

json.dumps(json.loads("".join(out)))  # validate before emitting
sys.stdout.write("".join(out))
'
