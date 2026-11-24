# Resumable: make_clip.py skips finished chunks; finished clips are skipped here.
S=/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad
cd $S/avatar2
PY=/root/ditto/venv/bin/python
for spec in "ava ava-1-blazer 1.5" "ethan ethan-v3a2 1.5" "sofia sofia-v3a1 1.5" "diego diego-v3c1 1.3"; do
  set -- $spec; c=$1; img=$2; exp=$3
  [ -f videos/$c-demo.mp4 ] && continue
  $PY make_clip.py $S/deliver2/$img.jpg audio/$c-coachonly.wav videos/$c-face.mp4 --exp-scale $exp --threads 4 >> logs/render-$c.log 2>&1 || { echo "fail $c" >> logs/render-all.log; continue; }
  ffmpeg -loglevel error -y -i videos/$c-face.mp4 -i audio/$c-mix.wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 128k -shortest -movflags +faststart videos/$c-demo.mp4 && echo "done $c $(date -u +%T)" >> logs/render-all.log
done
