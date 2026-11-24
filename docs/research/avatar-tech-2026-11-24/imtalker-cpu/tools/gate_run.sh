cd /tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad/imtalker
S=..
while true; do
  n=$(pgrep -f musetalk | grep -v $$ | wc -l); a=$(free -g | awk '/Mem:/{print $7}')
  echo "$(date +%T) musetalk_procs=$n avail_gb=$a"
  if ! pgrep -f "musetalk/(venv|tools/run)" >/dev/null && [ "$a" -ge 7 ]; then break; fi
  sleep 60
done
export FACE_LANDMARKER=$S/face_landmarker.task THREADS=4
mkdir -p out
echo "$(date +%T) START closed"
venv/bin/python -I tools/run_cpu.py src ckpt $S/softsmile/ava-1-blazer-soft-17-fixed.png $S/musetalk/in/ava-coach-26-36.wav out/ava-imtalker-closed.mp4 out/crop-closed.png 2>&1 | grep -v -e "^W0000" -e "^I0000"
echo "$(date +%T) DONE closed"
a=$(free -g | awk '/Mem:/{print $7}')
if [ "$a" -ge 7 ] && ! pgrep -f "musetalk/(venv|tools/run)" >/dev/null; then
  echo "$(date +%T) START open"
  venv/bin/python -I tools/run_cpu.py src ckpt $S/softsmile/ava-1-blazer.png $S/musetalk/in/ava-coach-26-36.wav out/ava-imtalker-opensmile.mp4 out/crop-open.png 2>&1 | grep -v -e "^W0000" -e "^I0000"
  echo "$(date +%T) DONE open"
else echo "skip open: avail=$a"; fi
echo GATE_ALL_DONE
