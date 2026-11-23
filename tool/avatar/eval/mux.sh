#!/usr/bin/env bash
# Mux rendered PNG frames + demo audio (delayed by the 0.8 s lead) into MP4s, plus a 2x2 grid per language.
set -euo pipefail
# Usage: mux.sh <demo dir containing jobs/ and render/>
D="${1:?demo dir}"
cd "$D"
for j in jobs/*.json; do
  n=$(basename "$j" .json)
  r="render/$n"
  frames=$(ls "$r" | wc -l)
  dur=$(python3 -c "print($frames/30)")
  ffmpeg -y -loglevel error -framerate 30 -i "$r/f%05d.png" -i "jobs/$n.wav" \
    -filter_complex "[1:a]adelay=800|800,apad[a]" -map 0:v -map "[a]" -t "$dur" \
    -c:v libx264 -pix_fmt yuv420p -crf 20 -movflags +faststart -c:a aac -b:a 128k "$n.mp4"
  echo "$n.mp4 $(du -h "$n.mp4" | cut -f1)"
done
for s in render/states-*/; do
  n=$(basename "$s")
  ffmpeg -y -loglevel error -framerate 30 -i "$s/f%05d.png" -c:v libx264 -pix_fmt yuv420p -crf 20 "$n-listen-think-idle.mp4"
  echo "$n-listen-think-idle.mp4"
done
for l in en es; do
  ffmpeg -y -loglevel error -i ava-$l.mp4 -i ethan-$l.mp4 -i sofia-$l.mp4 -i diego-$l.mp4 -filter_complex \
   "[0:v]scale=480:270,tpad=stop_mode=clone:stop_duration=3[a];[1:v]scale=480:270,tpad=stop_mode=clone:stop_duration=3[b];[2:v]scale=480:270,tpad=stop_mode=clone:stop_duration=3[c];[3:v]scale=480:270,tpad=stop_mode=clone:stop_duration=3[d];[a][b]hstack[t];[c][d]hstack[u];[t][u]vstack[v]" \
   -map "[v]" -an -t 10 -c:v libx264 -pix_fmt yuv420p -crf 23 all-coaches-$l-silent-grid.mp4
done
