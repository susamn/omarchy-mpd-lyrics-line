#!/bin/bash
# Emits current MPD track information and 4-line synced lyrics window as JSON.
# Line 0: 1 line above (previous context)
# Line 1: current singing line (highlighted)
# Line 2: 1 line below (upcoming context)
# Line 3: 2 lines below (upcoming context)

title=$(mpc current -f '%title%' 2>/dev/null)
artist=$(mpc current -f '%artist%' 2>/dev/null)
[ -z "$title" ] && title=$(mpc current -f '%file%' 2>/dev/null)

if [ -z "$title" ]; then
    jq -cn '{state: "stopped", title: "", artist: "", lines: ["", "", "", ""], hasLyrics: false}'
    exit 0
fi

raw_lyrics=$(mpdtui -lyrics-line 2>/dev/null)
l0=$(echo "$raw_lyrics" | sed -n '1p')
l1=$(echo "$raw_lyrics" | sed -n '2p')
l2=$(echo "$raw_lyrics" | sed -n '3p')
l3=$(echo "$raw_lyrics" | sed -n '4p')

has_lyrics=false
if [ -n "$l0" ] || [ -n "$l1" ] || [ -n "$l2" ] || [ -n "$l3" ]; then
    has_lyrics=true
fi

jq -cn \
  --arg title "$title" \
  --arg artist "$artist" \
  --arg l0 "$l0" --arg l1 "$l1" --arg l2 "$l2" --arg l3 "$l3" \
  --argjson hasLyrics "$has_lyrics" \
  '{state: "playing", title: $title, artist: $artist, lines: [$l0, $l1, $l2, $l3], hasLyrics: $hasLyrics}'
