from eyes_meas import *
import shutil
def lab_(img):
    l=cv2.cvtColor(img,cv2.COLOR_BGR2LAB).astype(np.float32);l[...,0]*=100/255.;l[...,1:]-=128;return l
def unlab_(l):
    l=l.copy();l[...,0]*=255/100.;l[...,1:]+=128;return cv2.cvtColor(np.clip(l,0,255).astype(np.uint8),cv2.COLOR_LAB2BGR)
def iris_weight(img,pt,iod,sig=0.085):
    H,W=img.shape[:2];L=lab_(img);yy,xx=np.mgrid[0:H,0:W].astype(np.float32)
    d2=((xx-pt[0])**2+(yy-pt[1])**2)/(sig*iod)**2
    ch=np.hypot(L[...,1],L[...,2])
    w=np.clip((L[...,0]-8)/4,0,1)*np.clip((44-L[...,0])/8,0,1)*np.clip((ch-2.5)/2,0,1)*np.exp(-d2)
    return cv2.GaussianBlur(w,(0,0),0.8)
def fix_gaze(c,fdir,out,iters=4,damp=0.9,bump=None):
    m,hero=setup(c,fdir);mst=verify.analyse(hero);f=mst['face'];iod=float(np.hypot(f[6]-f[4],f[7]-f[5]))
    pm=per_eye(hero,f);x,y,w,h=m['frames']['gaze']['rect']
    patch=cv2.imread(f'{fdir}/{c}/gaze.jpg')
    for it in range(iters):
        im=hero.copy();im[y:y+h,x:x+w]=patch;a=verify.analyse(im);fg=a['face']
        pe=per_eye(im,fg);L=lab_(im)
        for i,(ei) in enumerate(((4,5),(6,7))):
            pt=(fg[ei[0]],fg[ei[1]]);wm=iris_weight(im,pt,iod)
            dlt=(pm[i]-pe[i])*damp
            L[...,0]+=wm*dlt[0];L[...,1]+=wm*dlt[1];L[...,2]+=wm*dlt[2]
        im2=unlab_(L)
        patch=im2[y:y+h,x:x+w]
    os.makedirs(f'{out}/{c}',exist_ok=True)
    cv2.imwrite(f'{out}/{c}/gaze.jpg',patch,[cv2.IMWRITE_JPEG_QUALITY,92])
    return patch
if __name__=='__main__':
    fdir='/home/user/datewiseaiapp/assets/avatar';out=sys.argv[1]
    for c in ['ava','ethan','sofia','diego']:
        fix_gaze(c,fdir,out)
