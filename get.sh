#!/bin/bash


curl -s "https://universalis.com/Australia/jsonpmass.js" \
  | sed -E 's/^universalisCallback\((.*)\);?$/\1/'
