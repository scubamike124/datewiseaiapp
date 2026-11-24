# Photoreal coach portrait candidates (RealVisXL V5.0 Lightning, CreativeML OpenRAIL++-M) on CPU (bf16/AMX).
import torch, time, sys, json, os
from diffusers import StableDiffusionXLPipeline, DPMSolverMultistepScheduler
torch.set_num_threads(4)
OUT = "/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad/portraits"
os.makedirs(OUT, exist_ok=True)
pipe = StableDiffusionXLPipeline.from_pretrained("SG161222/RealVisXL_V5.0_Lightning", torch_dtype=torch.bfloat16, variant="fp16")
pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config, algorithm_type="sde-dpmsolver++", use_karras_sigmas=True)
pipe.set_progress_bar_config(disable=True)
# Kept under CLIP's 77-token limit: identity first, then scene, then camera.
COACH = {
  "ava":   "28 year old woman, long wavy auburn hair, dark brown eyes, faint freckles, natural warm smile, real skin texture",
  "ethan": "30 year old man, short tousled dark brown hair, dark brown eyes, light stubble, relaxed closed-mouth smile, natural skin",
  "sofia": "29 year old Mexican woman, long dark brown wavy hair, dark brown eyes, small gold hoop earrings, warm smile, real skin texture",
  "diego": "31 year old Mexican man, short black hair, short neat full beard, dark brown eyes, calm kind closed-mouth smile, natural skin",
}
SCENES = {
  "ava":   {"a": "white shirt buttoned to the collar, by a window, soft daylight", "b": "cream knit sweater, cozy cafe, warm light, soft bokeh", "c": "denim jacket over white t-shirt, city park, golden hour"},
  "ethan": {"a": "charcoal crewneck sweater, bright modern office, soft window light", "b": "navy button-up shirt, sunny street cafe terrace, soft bokeh", "c": "light grey t-shirt under olive jacket, city waterfront, late afternoon light"},
  "sofia": {"a": "terracotta linen blouse, sunlit courtyard with plants, soft shade", "b": "black blouse, cozy restaurant, warm evening light, bokeh", "c": "white blouse, colorful city street, soft daylight"},
  "diego": {"a": "white linen shirt, sunlit plaza, soft afternoon light", "b": "dark green button-up shirt, cozy coffee shop, warm light, bokeh", "c": "navy polo shirt, park with trees, golden hour"},
}
NEG = ("cartoon, illustration, 3d render, cgi, airbrushed, plastic skin, waxy skin, doll, oversaturated, heavy makeup, "
       "hdr, oversharpened, harsh contrast, deep wrinkles, old, cleavage, deformed eyes, cross-eyed, blue eyes, green eyes, extra teeth, watermark, text")
jobs = json.loads(sys.argv[1])  # [[coach, name, scene, seed], ...]
for coach, name, scene, seed in jobs:
    t = time.time()
    prompt = f"RAW photo, candid head and shoulders portrait of a {COACH[coach]}, {SCENES[coach][scene]}, looking at camera, 85mm f/1.8, natural colors"
    img = pipe(prompt=prompt, negative_prompt=NEG, num_inference_steps=8, guidance_scale=1.3, width=896, height=1152,
               generator=torch.Generator().manual_seed(seed)).images[0]
    img.save(f"{OUT}/{coach}-v3{name}.png")
    print("done", coach, name, round(time.time() - t), "s", flush=True)
