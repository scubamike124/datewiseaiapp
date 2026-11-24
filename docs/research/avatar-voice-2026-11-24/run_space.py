import sys, shutil, time, traceback
from gradio_client import Client, handle_file
space, coach, audio, out = sys.argv[1:5]
img = f"/home/user/datewiseaiapp/assets/coaches/{coach}-hero.jpg"
t = time.time()
try:
    c = Client(space, verbose=False)
    if space == "alexnasa/OmniAvatar":
        r = c.predict(handle_file(img), handle_file(audio),
                      "A realistic video of a person speaking naturally to the camera, with natural blinking, subtle smiles and gentle head movements.",
                      8, api_name="/infer_scene")
        path = r["video"] if isinstance(r, dict) else r
    elif space == "acvlab/FantasyTalking":
        ep = [e for e in c.view_api(return_format="dict")["named_endpoints"]]
        print("endpoints", ep, flush=True)
        r = c.predict(handle_file(img), handle_file(audio), api_name=ep[0])
        path = r["video"] if isinstance(r, dict) else r
    shutil.copy(path, out)
    print("OK", space, coach, round(time.time() - t), "s ->", out, flush=True)
except Exception as e:
    print("FAIL", space, coach, round(time.time() - t), "s", repr(e)[:400], flush=True)
