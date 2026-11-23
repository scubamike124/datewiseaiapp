import sys, os, math, numpy as np, cv2
SP=os.environ.get('DW_PORTRAIT_WORK', os.path.expanduser('~/dw-portrait-work'))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import portrait_intake as pi
C=['ava','ethan','sofia','diego']
_refs=None
def refs():
    global _refs
    if _refs is None: _refs=pi.ref_data()
    return _refs
def face(img):
    fs=pi.faces(img)
    if not fs:  # YuNet misses very large faces: retry on a smaller copy
        for m in (1280,1024):
            s=m/max(img.shape[:2])
            if s<1:
                g=pi.faces(cv2.resize(img,None,fx=s,fy=s,interpolation=cv2.INTER_AREA))
                if g:
                    fs=[x.copy() for x in g]
                    for x in fs: x[:14]/=s
                    break
    return max(fs,key=lambda x:x[2]*x[3]) if fs else None
def stats(img, coach):
    f=face(img); R=refs()
    e=pi.embed(img,f)
    sims={c:round(float(pi.rec.match(e,R[c][0],cv2.FaceRecognizerSF_FR_COSINE)),3) for c in C}
    t=pi.eye_tone(img,f); rt=R[coach][1]
    dh=min(abs(t[0]-rt[0]),180-abs(t[0]-rt[0])); dv=abs(t[2]-rt[2])
    roll=math.degrees(math.atan2(f[7]-f[5],f[6]-f[4]))
    return dict(sim=sims[coach], sims=sims, eye=(round(dh,1),round(dv,1)), roll=round(roll,1), fw=int(f[2]), fh=int(f[3]), emb=e)
def cross(a,b):
    return round(float(pi.rec.match(a,b,cv2.FaceRecognizerSF_FR_COSINE)),3)
def sheet(rows, path, h=360):
    """rows: list of lists of BGR images; each row's images are scaled to height h."""
    R=[np.hstack([cv2.resize(i,(int(i.shape[1]*h/i.shape[0]),h)) for i in r]) for r in rows]
    W=max(r.shape[1] for r in R)
    R=[np.pad(r,((0,0),(0,W-r.shape[1]),(0,0))) for r in R]
    cv2.imwrite(path,np.vstack(R),[cv2.IMWRITE_JPEG_QUALITY,88])
