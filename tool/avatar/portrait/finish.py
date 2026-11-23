# Stage C: upscale the SD result (Real-ESRGAN x4 via spandrel), composite the original face/hair back,
# replace the backdrop with a clean per-coach studio gradient, apply one shared grade, crop hero + avatar.
import sys, os, numpy as np, cv2, torch
SP=os.environ.get('DW_PORTRAIT_WORK', os.path.expanduser('~/dw-portrait-work'))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fl, seg
C=SP+'/fp/comp'; O=SP+'/fp/final'; os.makedirs(O,exist_ok=True)
ESR=[os.path.join(dp,f) for dp,_,fs in os.walk(os.path.expanduser('~/.cache/huggingface/hub/models--ai-forever--Real-ESRGAN')) for f in fs if f=='RealESRGAN_x4.pth'][0]
FACE_H=1024
TOP={'sofia':dict(lmul=0.38,ladd=0,cmul=0.4),'ava':dict(lmul=0.97,ladd=0,cmul=1.0,da=1,db=6)}  # Sofia: grey knit -> black; Ava: white -> ivory
OUT=SP+'/fp/out'; os.makedirs(OUT,exist_ok=True)  # target YuNet face-box height in the hero
# backdrop: centre colour, edge colour (BGR) - dark, muted, distinct per coach
BG={'ava':((96,88,44),(44,40,18)), 'ethan':((104,78,58),(46,34,24)), 'sofia':((60,80,132),(24,32,60)), 'diego':((58,92,80),(24,40,34))}
_m=None
def esrgan(bgr):
    global _m
    if _m is None:
        from spandrel import ModelLoader
        _m=ModelLoader().load_from_file(ESR).eval()
    t=torch.from_numpy(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB).astype(np.float32)/255).permute(2,0,1)[None]
    with torch.no_grad(): o=_m(t)[0].clamp(0,1).permute(1,2,0).numpy()
    return cv2.cvtColor((o*255).round().astype(np.uint8),cv2.COLOR_RGB2BGR)
def backdrop(c,W,H):
    cc,ec=[np.array(x,np.float32) for x in BG[c]]
    yy,xx=np.mgrid[0:H,0:W].astype(np.float32)
    d=np.sqrt(((xx-W*0.5)/(W*0.75))**2+((yy-H*0.36)/(H*0.7))**2); t=np.clip(d,0,1)**1.4
    b=cc*(1-t[...,None])+ec*t[...,None]
    n=np.random.default_rng(7).normal(0,1.2,(H//4+1,W//4+1)).astype(np.float32)
    b+=cv2.resize(n,(W,H))[...,None]
    return b
def grade(img):
    x=img.astype(np.float32)/255
    x=np.clip((x-0.5)*1.04+0.5,0,1)            # gentle contrast
    x=x**1.03                                   # a touch deeper for the dark theme
    return np.clip(x*255,0,255).astype(np.uint8)
def run(c, seed):
    frame=cv2.imread(f'{C}/{c}-frame.png'); keep=np.load(f'{C}/{c}-keep.npy').astype(np.float32)
    fb=np.load(f'{C}/{c}-fb.npy'); H0,W0=frame.shape[:2]
    s=FACE_H/fb[3]; W,H=int(round(W0*s/8)*8),int(round(H0*s/8)*8)
    sd=cv2.imread(f'{C}/{c}-sd{seed}.png')
    esr=cv2.resize(esrgan(sd),(W,H),interpolation=cv2.INTER_AREA)
    lz=cv2.resize(sd,(W,H),interpolation=cv2.INTER_LANCZOS4)
    up=cv2.GaussianBlur(cv2.addWeighted(esr,0.55,lz,0.45,0),(0,0),0.9)  # ESRGAN's knit-texture moire toned down
    orig=cv2.resize(frame,(W,H),interpolation=cv2.INTER_LANCZOS4)
    k=cv2.resize(keep,(W,H),interpolation=cv2.INTER_LINEAR)
    k=cv2.GaussianBlur(cv2.erode(k,np.ones((5,5))),(0,0),4)   # feathered seam, face itself stays original
    comp=orig.astype(np.float32)*k[...,None]+up.astype(np.float32)*(1-k[...,None])
    comp=np.clip(comp,0,255).astype(np.uint8)
    # clean backdrop: person matte from the segmenter (background class), softened
    # Backdrop recolour, not a cut-out: every pixel moves by (new backdrop - old backdrop) weighted by the
    # segmenter's soft background probability, so hair strands and soft edges keep their texture.
    Pm=seg.segment(comp); p=cv2.GaussianBlur(np.clip(Pm[...,0]-Pm[...,4]-Pm[...,2],0,1),(0,0),1.5)
    if c in TOP:
        sys.path.insert(0,SP+'/fp/bin'); from style import lab_edit
        tm=cv2.GaussianBlur(Pm[...,4],(0,0),2)*(1-k)
        comp=lab_edit(comp,tm,**TOP[c])
    cf=comp.astype(np.float32); sig=W/14
    hairp=Pm[...,1]
    sure=(p>0.85).astype(np.float32)
    if True:   # the segmenter can call a plain shoulder "background": also require the old backdrop's colour
        num=cv2.GaussianBlur(cf*sure[...,None],(0,0),sig); den=cv2.GaussianBlur(sure,(0,0),sig)[...,None]+1e-4
        old=num/den                                   # smooth estimate of the old backdrop colour
        sim=np.exp(-(np.linalg.norm(cf-old,axis=-1)/30.0)**2)
        gate=np.maximum(sim,(hairp>0.2).astype(np.float32))   # hair fringe keeps the segmenter's soft value
        p=np.minimum(p,gate)
        # seam band round the protected region: old-backdrop-coloured pixels there are backdrop (halo), whatever the segmenter says
        kb=(k>0.5).astype(np.uint8); band=cv2.dilate(kb,np.ones((41,41)))-cv2.erode(kb,np.ones((41,41)))
        facecore=cv2.erode((Pm[...,3]>0.5).astype(np.uint8),np.ones((9,9)))
        band=(band>0)&(facecore==0)
        p=np.where(band,np.maximum(p,sim*(sim>0.35)),p)
        # hair fringe: wisps carry the old (lighter) backdrop; there a looser colour match decides
        simw=np.exp(-(np.linalg.norm(cf-old,axis=-1)/60.0)**2)
        fringe=cv2.dilate((hairp>0.5).astype(np.uint8),np.ones((61,61)))&(hairp<0.85)&(facecore==0)
        p=np.where(fringe>0,np.maximum(p,simw*(1-hairp)),p)
        # only backdrop connected to the frame edge: an enclosed gap (collar/neck shadow) is not backdrop
        n,lab=cv2.connectedComponents((p>0.4).astype(np.uint8))
        edge=set(np.unique(np.concatenate([lab[0],lab[:,0],lab[:,-1]])))-{0}
        conn=np.isin(lab,list(edge)).astype(np.uint8)
        conn=cv2.dilate(conn,np.ones((9,9)))
        p=p*conn
        p=cv2.GaussianBlur(p,(0,0),1.2)
    bd=backdrop(c,W,H)
    out=cf+p[...,None]*(bd-old)
    # flatten residual backdrop texture a little (SD painted some mottling)
    out=out*(1-0.6*p[...,None])+cv2.GaussianBlur(out,(0,0),6)*(0.6*p[...,None])
    # gentle detail lift on the original face/hair region (unsharp, no face restoration) + shared fine grain
    o8=np.clip(out,0,255).astype(np.float32)
    o8=o8+0.25*(k**2)[...,None]*(o8-cv2.GaussianBlur(o8,(0,0),1.6))
    o8+=np.random.default_rng(11).normal(0,1.6,(H,W))[...,None]
    out=grade(np.clip(o8,0,255).astype(np.uint8))
    cv2.imwrite(f'{O}/{c}-hero-s{seed}.png',out)
    np.save(f'{O}/{c}-k.npy',(k*255).astype(np.uint8))
    print(c,seed,'hero',out.shape,flush=True)
    cv2.imwrite(f'{OUT}/{c}-hero.jpg',out,[cv2.IMWRITE_JPEG_QUALITY,92])
    f=fl.face(out); cx,cy=f[0]+f[2]/2,f[1]+f[3]/2+0.05*f[3]; side=int(min(1.9*f[3],W,H))
    x0=int(np.clip(cx-side/2,0,W-side)); y0=int(np.clip(cy-side/2,0,H-side))
    cv2.imwrite(f'{OUT}/{c}-avatar.jpg',cv2.resize(out[y0:y0+side,x0:x0+side],(1024,1024),interpolation=cv2.INTER_AREA),[cv2.IMWRITE_JPEG_QUALITY,92])
    return out
if __name__=='__main__':
    for c in sys.argv[1].split(','): run(c,int(sys.argv[2]))
