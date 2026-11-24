W=/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad/musetalk
while pgrep -f softsmile/inpaint.py >/dev/null; do echo "$(date +%T) waiting for inpaint"; sleep 60; done
echo "$(date +%T) inpaint gone; free:"; free -m | head -2
cd $W/repo
export TORCH_HOME=$W/torchhome OMP_NUM_THREADS=4 MKL_NUM_THREADS=4
$W/venv/bin/python $W/tools/peakmem.py $W/run-stats.json $W/venv/bin/python -m scripts.inference   --inference_config $W/in/ava.yaml --result_dir $W/results --unet_model_path ./models/musetalkV15/unet.pth   --unet_config ./models/musetalkV15/musetalk.json --version v15 --batch_size 4 --saved_coord
echo "$(date +%T) RUN_DONE"
