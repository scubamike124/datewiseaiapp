import os
# Stage B: portrait framing. Everything outside the protected face+hair region is (re)generated with
# SD 1.5 inpainting (CreativeML OpenRAIL-M) at low resolution, upscaled with Real-ESRGAN, and the
# original face/hair pixels are composited back on top at full resolution.
import sys, os, numpy as np, cv2, torch
SP=os.environ.get('DW_PORTRAIT_WORK', os.path.expanduser('~/dw-portrait-work'))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fl
S=SP+'/fp/styled'; O=SP+'/fp/comp'; os.makedirs(O,exist_ok=True)
NEG=("hunched, raised shoulder, asymmetric shoulders, mesh, fishnet, net texture, plastic, sequins, glitter, sparkles, shiny fabric, bare chest, cleavage, hands, fingers, hand, arm raised, necklace, text, watermark, logo, extra person, deformed, disfigured, blurry, "
     "cartoon, painting, illustration, busy background, furniture, window, plant, bad anatomy, collage")
P={
 'ava':  ("professional studio headshot photo of a young woman with auburn shoulder-length wavy hair, wearing a plain matte ivory cotton button-up shirt with a collar, "
          "plain dark grey studio backdrop, soft even key light, photorealistic, sharp focus, 85mm", (92,84,38)),
 'ethan':("professional studio headshot photo of a man, wearing a fine-knit camel merino crew-neck sweater, level symmetrical relaxed shoulders, front-facing upper body, "
          "plain dark grey studio backdrop, soft even key light, photorealistic, sharp focus, 85mm", (98,72,52)),
 'sofia':("professional studio headshot photo of a young woman with long dark wavy hair flowing over her shoulders, wearing a black fitted crew-neck knit top with a high round neckline, "
          "plain dark grey studio backdrop, soft even key light, photorealistic, sharp focus, 85mm", (52,70,120)),
 'diego':("professional studio headshot photo of a man, wearing a white linen shirt with an open collar, relaxed shoulders, "
          "plain dark grey studio backdrop, soft even key light, photorealistic, sharp focus, 85mm", (50,86,76)),
}
WK=(512,680)   # SD working size (w,h)
def frame(c):
    img=cv2.imread(f'{S}/{c}.png'); Pm=np.load(f'{S}/{c}-seg.npy').astype(np.float32)
    v=cv2.imread(f'{SP}/fp/neutral/{c}-valid.png',0).astype(np.float32)/255
    f=np.load(f'{S}/{c}-face.npy'); x,y,w,h=f[:4]
    W=2.25*w; H=W*4/3; cx=x+w/2; top=y-0.5*h
    X0,Y0=int(round(cx-W/2)),int(round(top)); W,H=int(round(W)),int(round(H))
    def cut(a,fill):
        pad=800; a=cv2.copyMakeBorder(a,pad,pad,pad,pad,cv2.BORDER_CONSTANT,value=fill)
        return a[Y0+pad:Y0+pad+H,X0+pad:X0+pad+W]
    return cut(img,0), cut(Pm,0), cut(v,0), (f[:4]-[X0,Y0,0,0]), (X0,Y0,W,H)
def protect_mask(c,Pm,v,fb):
    x,y,w,h=fb
    valid=cv2.erode((v>0.99).astype(np.uint8),np.ones((9,9)))
    face=(Pm[...,3]>0.5).astype(np.uint8)
    hair=cv2.erode((Pm[...,1]>0.6).astype(np.uint8),np.ones((7,7)))   # hair fringe is regenerated over the new backdrop
    ear=(Pm[...,5]>0.4).astype(np.uint8); ear[:int(y),:]=0              # earrings
    neck=(Pm[...,2]>0.5).astype(np.uint8); neck[int(y+h+(0.12 if c=='diego' else 0.28)*h):,:]=0   # upper neck only
    if c=='ethan': neck[:]=0                                            # his hand under the chin is regenerated (neck + collar)
    core=face.copy()
    face=cv2.dilate(face,np.ones((13,13)))                              # face plus a margin is never generated
    face[(Pm[...,3]<0.2)&(Pm[...,1]<0.3)&(Pm[...,2]<0.3)&(core==0)]=0   # ...margin = pixels with some face/skin/hair score; clothing/backdrop are not face
    if c=='ethan':
        hand=(Pm[...,2]>0.5).astype(np.uint8); hand[:int(y+0.75*h),:]=0
        face[cv2.dilate(hand,np.ones((9,9)))>0]=0
    m=((face|hair|ear|neck)&valid)
    # fill holes (inside of hoop earrings, gaps between face and hair): those stay original too
    ff=np.pad(m,1).copy(); cv2.floodFill(ff,None,(0,0),2); m=(m|(ff[1:-1,1:-1]==0)).astype(np.uint8)&valid
    # drop small islands
    n,lab,stt,_=cv2.connectedComponentsWithStats(m)
    keep=np.zeros_like(m)
    for i in range(1,n):
        if stt[i,4]>2000: keep[lab==i]=1
    return keep
_pipe=None
def pipe():
    global _pipe
    if _pipe is None:
        from diffusers import StableDiffusionInpaintPipeline, DPMSolverMultistepScheduler
        p=StableDiffusionInpaintPipeline.from_pretrained(SP+'/fp/sd-inpaint',variant='fp16',torch_dtype=torch.float32,safety_checker=None,feature_extractor=None,requires_safety_checker=False)
        p.scheduler=DPMSolverMultistepScheduler.from_config(p.scheduler.config,use_karras_sigmas=True)
        p.set_progress_bar_config(disable=True); _pipe=p
    return _pipe
def generate(c, seeds, steps=20):
    from PIL import Image
    img,Pm,v,fb,box=frame(c)
    keep=protect_mask(c,Pm,v,fb)
    prompt,bg=P[c]
    init=img.copy()
    gen=(keep==0)
    init[gen]=(90,90,90)  # prefill with the backdrop colour
    m=cv2.resize((gen*255).astype(np.uint8),WK,interpolation=cv2.INTER_AREA)
    m=cv2.dilate((m>40).astype(np.uint8)*255,np.ones((5,5)))
    im=cv2.resize(init,WK,interpolation=cv2.INTER_AREA)
    np.save(f'{O}/{c}-keep.npy',keep); cv2.imwrite(f'{O}/{c}-frame.png',img); np.save(f'{O}/{c}-box.npy',np.array(box)); np.save(f'{O}/{c}-fb.npy',fb)
    cv2.imwrite(f'{O}/{c}-init.png',im); cv2.imwrite(f'{O}/{c}-mask.png',m)
    for s in seeds:
        r=pipe()(prompt=prompt,negative_prompt=NEG,image=Image.fromarray(cv2.cvtColor(im,cv2.COLOR_BGR2RGB)),mask_image=Image.fromarray(m),
                 width=WK[0],height=WK[1],num_inference_steps=steps,guidance_scale=7.0,strength=1.0,
                 generator=torch.Generator().manual_seed(s)).images[0]
        cv2.imwrite(f'{O}/{c}-sd{s}.png',cv2.cvtColor(np.array(r),cv2.COLOR_RGB2BGR)); print(c,'seed',s,'done',flush=True)
def rekeep(c):
    img,Pm,v,fb,box=frame(c); np.save(f'{O}/{c}-keep.npy',protect_mask(c,Pm,v,fb))
if __name__=='__main__':
    if sys.argv[1]=='rekeep':
        for c in sys.argv[2].split(','): rekeep(c)
        sys.exit()
    torch.set_num_threads(4)
    seeds=[int(s) for s in sys.argv[2].split(',')]
    for c in sys.argv[1].split(','): generate(c,seeds)
