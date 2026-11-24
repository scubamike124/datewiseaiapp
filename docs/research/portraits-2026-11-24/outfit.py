import torch, time
from PIL import Image, ImageFilter
from diffusers import StableDiffusionXLInpaintPipeline, DPMSolverMultistepScheduler
torch.set_num_threads(4)
pipe = StableDiffusionXLInpaintPipeline.from_pretrained("SG161222/RealVisXL_V5.0_Lightning", torch_dtype=torch.bfloat16, variant="fp16")
pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config, algorithm_type="sde-dpmsolver++", use_karras_sigmas=True)
pipe.set_progress_bar_config(disable=True)
P = "RAW photo, woman wearing a tailored navy blazer over a crisp white blouse, professional, natural fabric texture, soft cafe light, 85mm"
N = "sweater, knit, cleavage, low neckline, logo, text, cartoon, cgi, deformed hands, extra fingers"
for n in ['ava-v2b3', 'ava-b1', 'ava-v2b4']:
    for seed in (11, 23):
        t = time.time()
        img = Image.open(f'retouch/{n}-iris.png').convert('RGB')
        mask = Image.open(f'retouch/{n}-clothes-mask.png').convert('L').filter(ImageFilter.GaussianBlur(4))
        out = pipe(prompt=P, negative_prompt=N, image=img, mask_image=mask, strength=0.99, num_inference_steps=10,
                   guidance_scale=1.6, width=896, height=1152, generator=torch.Generator().manual_seed(seed)).images[0]
        # paste back only the masked region so the face and hair stay pixel-identical
        Image.composite(out, img, mask).save(f'retouch/{n}-blazer-{seed}.png')
        print('done', n, seed, round(time.time() - t), 's', flush=True)
