import torch, time
from PIL import Image, ImageFilter
from diffusers import StableDiffusionXLInpaintPipeline, DPMSolverMultistepScheduler
torch.set_num_threads(4)
D='/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad/softsmile/'
pipe = StableDiffusionXLInpaintPipeline.from_pretrained("SG161222/RealVisXL_V5.0_Lightning", torch_dtype=torch.bfloat16, variant="fp16")
pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config, algorithm_type="sde-dpmsolver++", use_karras_sigmas=True)
pipe.set_progress_bar_config(disable=True)
P = {'ava-1-blazer': 'RAW photo, close-up of a young woman, lips closed, gentle soft closed-mouth smile, natural lips, freckles, real skin',
     'ethan-v3a2': 'RAW photo, close-up of a man, lips closed, gentle soft closed-mouth smile, light stubble, natural lips, real skin',
     'sofia-v3a1': 'RAW photo, close-up of a young woman, lips closed, gentle soft closed-mouth smile, natural lips, real skin'}
N = 'teeth, open mouth, toothy grin, laughing, cartoon, cgi, deformed lips, lipstick'
for n, p in P.items():
    img = Image.open(D + n + '.png').convert('RGB'); W, H = img.size
    mask = Image.open(D + n + '-mask.png').convert('L').filter(ImageFilter.GaussianBlur(6))
    for seed in (3, 17):
        t = time.time()
        out = pipe(prompt=p, negative_prompt=N, image=img, mask_image=mask, strength=0.8, num_inference_steps=10, guidance_scale=1.8,
                   width=W - W % 8, height=H - H % 8, generator=torch.Generator().manual_seed(seed)).images[0].resize((W, H))
        Image.composite(out, img, mask).save(f'{D}{n}-soft-{seed}.png')
        print('done', n, seed, round(time.time() - t), flush=True)
