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
final_gif="$PWD/.vapor/flemma_cast_with_poster.gif"

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

# Build the Reddit GIF from VHS's clean 1080p gif — deliberately NOT from the mp4: routing frames through H.264
# (yuv420p) reintroduces per-pixel noise that defeats GIF inter-frame compression and roughly doubles the file.
# Downscale to Reddit size and prepend the SAME poster frame chosen for the MP4 in a single global-palette pass
# (palettegen/paletteuse; a plain -c copy concat can't splice across GIF palettes), looping forever (-loop 0).
# The poster shows for one frame (~1/GIF_FPS s) at the top of each loop. This is the slow step, so it renders at
# GIF_HEIGHT/GIF_FPS, not the mp4's 1080p/25 — the mp4 stays the full-res hero.
GIF_HEIGHT=540 # Reddit display height; width auto-derived, kept 16:9 and even
GIF_FPS=15     # smooth enough for a terminal demo at roughly half the frames
GIF_DITHER=sierra2_4a
cast_gif="${cast%.mp4}.gif"
if [[ -f "$cast_gif" ]]; then
  scale="scale=-2:${GIF_HEIGHT}:flags=lanczos"
  ffmpeg -hide_banner -y \
    -loop 1 -t 1 -i "$poster_jpg" \
    -i "$cast_gif" \
    -filter_complex "[0:v]fps=${GIF_FPS},${scale},setsar=1,trim=end_frame=1[p];[1:v]fps=${GIF_FPS},${scale},setsar=1[g];[p][g]concat=n=2:v=1:a=0[v];[v]split[v1][v2];[v1]palettegen=stats_mode=full[pal];[v2][pal]paletteuse=dither=${GIF_DITHER}[o]" \
    -map "[o]" -loop 0 "$final_gif"
  mv "$final_gif" "$cast_gif"
fi

rm -f "$poster_jpg" "$poster_mp4" "$concat_list" "$final_gif"
