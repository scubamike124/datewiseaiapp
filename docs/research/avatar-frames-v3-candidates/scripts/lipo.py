from lib import *
from ov_o import lipmask,soft_o2
import sys
sys.path.insert(0,'.')
def mxy(c):
    m=man(c);x0,y0=m['frames']['a']['rect'][:2];return m['mouth'][0]-x0,m['mouth'][1]-y0,m['mouth_width']
def lipmask2(img,c,m_a=7):
    from ov import ell
    L=lab(img);e=ell(c,img.shape,0.75,0.5,0.1);ring=(cv2.dilate(e,np.ones((15,15),np.uint8))-e)>0
    ring&=(L[...,0]>35);sk=np.median(L[...,1][ring])
    lp=((L[...,1]>sk+m_a)&(e>0)).astype(np.uint8)
    lp=cv2.morphologyEx(lp,cv2.MORPH_OPEN,np.ones((3,3),np.uint8))
    lp=cv2.morphologyEx(lp,cv2.MORPH_CLOSE,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(9,9)))
    n,lb,st,_=cv2.connectedComponentsWithStats(lp);k=1+int(np.argmax(st[1:,4]));lp=(lb==k).astype(np.uint8)
    cnt,_=cv2.findContours(lp,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_NONE);f=np.zeros_like(lp);cv2.drawContours(f,cnt,-1,1,-1);return f
def lip_only(c,name,S=1.22,sv=1.04,feather=1.6):
    o=frame(c,name);H,W=o.shape[:2];mx,my,mw=mxy(c)
    M=lipmask2(o,c).astype(np.float32);M=cv2.dilate(M,np.ones((3,3),np.uint8))
    yy,xx=np.mgrid[0:H,0:W].astype(np.float32)
    # lip centre = centroid of mask
    ys,xs=np.nonzero(M);cx=float(xs.mean());cy=float(ys.mean())
    mapx=(cx+(xx-cx)/S).astype(np.float32);mapy=(cy+(yy-cy)/sv).astype(np.float32)
    ls=cv2.remap(o,mapx,mapy,cv2.INTER_CUBIC,borderMode=cv2.BORDER_REPLICATE)
    ms=cv2.remap(M,mapx,mapy,cv2.INTER_LINEAR,borderMode=cv2.BORDER_CONSTANT,borderValue=0)
    ms=cv2.GaussianBlur(ms,(0,0),feather)
    # keep the union so the original lip is always covered
    ms=np.maximum(ms,cv2.GaussianBlur(M,(0,0),feather)*0.0)
    out=o.astype(np.float32)*(1-ms[...,None])+ls.astype(np.float32)*ms[...,None]
    return np.clip(out,0,255).astype(np.uint8),M
if __name__=='__main__':
    c=sys.argv[1] if len(sys.argv)>1 else 'ethan';rows=[]
    for n in ['o','o2']:
        o,M=lip_only(c,n);v2=cv2.imread('../../avatar-frames-v2/'+f'{c}/{n}.jpg')
        rows.append(np.hstack([frame(c,n)[60:260,70:400],o[60:260,70:400],v2[60:260,70:400]]))
    cv2.imwrite('../work/lo-'+c+'.png',cv2.resize(np.vstack(rows),None,fx=1.6,fy=1.6,interpolation=cv2.INTER_CUBIC))

def blur_(a,s): return cv2.GaussianBlur(a.astype(np.float32),(0,0),s)
def remove_tails(o,c,hthick=11,pad=3):
    M=lipmask(o,7);H,W=M.shape;M[230:,:]=0
    h=M.sum(0);thick=np.nonzero(h>=hthick)[0];xl,xr=thick.min(),thick.max()
    tm=np.zeros_like(M)
    for x in range(W):
        if (x<xl or x>xr) and h[x]>0: tm[:,x]=M[:,x]
    ys=np.nonzero(M[:,xl:xl+8].any(1))[0];yc=int(np.median(ys))
    Lg=lab(o)[...,0];dev=blur_(Lg,7)-Lg
    box=np.zeros_like(M);box[max(0,yc-8):yc+9,max(0,xl-44):xl+1]=1
    t2=((dev>2.0)&(box>0)).astype(np.uint8)
    tm=np.maximum(tm,t2)
    tm=cv2.dilate(tm,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(pad*2+1,pad*2+1)))
    # also a wide band around where the tail ran, only on the columns outside the thick part
    return cv2.inpaint(o,tm*255,4,cv2.INPAINT_TELEA),tm

def remove_tail_box(o,box,thr=1.2,grow=2):
    x0,x1,y0,y1=box;L=lab(o)[...,0];a=lab(o)[...,1]
    dev=np.maximum(blur_(L,6)-L,0)+0.5*np.maximum(a-blur_(a,6),0)
    m=np.zeros(L.shape,np.uint8);m[y0:y1,x0:x1]=(dev[y0:y1,x0:x1]>thr)
    m=cv2.dilate(m,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(2*grow+1,2*grow+1)))
    return cv2.inpaint(o,m*255,5,cv2.INPAINT_TELEA),m
