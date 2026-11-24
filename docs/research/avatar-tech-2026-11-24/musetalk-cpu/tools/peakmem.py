# Run a command, sample RSS of the whole process tree every 0.5 s, report peak and wall time.
import sys, time, subprocess, psutil, json
t0 = time.time(); p = subprocess.Popen(sys.argv[2:]); pp = psutil.Process(p.pid); peak = 0
while p.poll() is None:
    try:
        rss = pp.memory_info().rss + sum(c.memory_info().rss for c in pp.children(recursive=True))
        peak = max(peak, rss)
    except psutil.Error: pass
    time.sleep(0.5)
res = {'rc': p.returncode, 'wall_s': round(time.time() - t0, 1), 'peak_rss_gb': round(peak / 1e9, 2)}
print('PEAKMEM', json.dumps(res)); json.dump(res, open(sys.argv[1], 'w'))
