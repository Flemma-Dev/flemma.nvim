#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $(basename "$0") <cast.mp4>" >&2
  exit 2
fi

cast=$(realpath "$1")
poster_jpg="$PWD/.vapor/poster.jpg"
poster_mp4="$PWD/.vapor/poster.mp4"
concat_list="$PWD/.vapor/concat_list.txt"
final_mp4="$PWD/.vapor/flemma_cast_with_poster.mp4"

while :; do
  read -rp "Timestamp for poster frame [MM:SS[.sss]] (o to open cast): " ts
  [[ -z "$ts" ]] && continue

  if [[ "$ts" =~ ^[Oo]$ ]]; then
    if command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$cast" >/dev/null 2>&1 &
    else
      echo "xdg-open not available; cast is at $cast" >&2
    fi
    continue
  fi

  if ! ffmpeg -hide_banner -y -ss "$ts" -i "$cast" \
    -vframes 1 -q:v 2 "$poster_jpg"; then
    continue
  fi

  echo "$poster_jpg"
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$poster_jpg" >/dev/null 2>&1 &
  fi

  read -rp "Use this frame? [y/N]: " ok
  [[ "$ok" =~ ^[Yy]$ ]] && break
done

ffmpeg -hide_banner -y -loop 1 -i "$poster_jpg" \
  -vframes 1 -r 60 -c:v libx264 -pix_fmt yuv420p "$poster_mp4"

printf 'file %s\nfile %s\n' "$poster_mp4" "$cast" >"$concat_list"

ffmpeg -hide_banner -y -f concat -safe 0 \
  -i "$concat_list" -c copy "$final_mp4"

mv "$final_mp4" "$cast"
rm -f "$poster_jpg" "$poster_mp4" "$concat_list"
