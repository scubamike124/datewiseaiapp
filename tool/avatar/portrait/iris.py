# Explicit iris-colour comparison: mean CIELAB of the darker iris pixels in a disc at each YuNet eye point,
# candidate vs the approved reference crop (upscaled 4x, cubic). Reports Delta-E76 and the hue angle.
import os
import sys, math, numpy as np, cv2
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fl
def iris(img):
    f=fl.face(img); vals=[]
    for ex,ey in [(f[4],f[5]),(f[6],f[7])]:
        r=max(3,int(f[2]*0.045)); yy,xx=np.mgrid[-r:r+1,-r:r+1]; d=(xx**2+yy**2)<=r*r
        p=img[int(ey)-r:int(ey)+r+1,int(ex)-r:int(ex)+r+1][d]
        lab=cv2.cvtColor(p[None].astype(np.uint8),cv2.COLOR_BGR2LAB)[0].astype(np.float32)
        lab[:,0]*=100/255; lab[:,1:]-=128
        sel=lab[lab[:,0]<np.percentile(lab[:,0],55)]; sel=sel[sel[:,0]>np.percentile(sel[:,0],25)]  # iris ring, not pupil, not white/highlight
        vals.append(sel.mean(0))
    return np.mean(vals,0)
def compare(img,c):
    ref=cv2.imread(f'{fl.SP}/dw-ref/crop-{c}.png'); ref=cv2.resize(ref,None,fx=4,fy=4,interpolation=cv2.INTER_CUBIC)
    # compare at the same face scale (the sampling disc and the percentiles depend on the pixel count)
    fr,fc=fl.face(ref),fl.face(img); img=cv2.resize(img,None,fx=fr[2]/fc[2],fy=fr[2]/fc[2],interpolation=cv2.INTER_AREA)
    a,b=iris(img),iris(ref)
    hue=lambda v: math.degrees(math.atan2(v[2],v[1]))%360
    dh=abs(hue(a)-hue(b)); dh=min(dh,360-dh)
    return dict(dE=round(float(np.linalg.norm(a-b)),1), hue_deg=round(hue(a),0), ref_hue_deg=round(hue(b),0), dhue=round(dh,0),
                b_cand=round(float(a[2]),1), b_ref=round(float(b[2]),1), brown=bool(a[2]>0)==bool(b[2]>0))
if __name__=='__main__':
    for p in sys.argv[2:]: print(p.split('/')[-1], compare(cv2.imread(p), sys.argv[1]))
