from eyefix2 import *
from eyefix2 import _paste
def gate_eye(c,hero,m,patch,mst):
    im=_paste(hero,patch,m['frames']['gaze']['rect']);a=verify.analyse(im);t,mm=a['tone'],mst['tone']
    return float(np.hypot(t[1]-mm[1],t[2]-mm[2])),float(abs(t[0]-mm[0]))
def run_k(c,fdir,k,iters=3,only=None):
    m,hero=setup(c,fdir);rect=m['frames']['gaze']['rect'];I=IRIS[c];r=I['r']
    patch=cv2.imread(f'{fdir}/{c}/gaze.jpg');full=_paste(hero,patch,rect)
    cr=[refine(hero,*p,r,rect) for p in I['rest']];cg=[refine(full,*p,r,rect) for p in I['gaze']]
    t=[stats(hero,p,r,rect) for p in cr];new=patch.copy()
    for it in range(iters):
        cur=_paste(hero,new,rect)
        for i in range(2):
            if only is not None and i not in only: continue
            st=stats(cur,cg[i],r,rect);delta=(t[i]-st)*k
            delta=np.array([np.clip(delta[0],-5,5),np.clip(delta[1],-4,4),np.clip(delta[2],-4,4)])
            new=correct(new,cg[i],r,(0,0,rect[2],rect[3]),delta,0.9)
    return new,m,hero
if __name__=='__main__':
    fdir='/home/user/datewiseaiapp/assets/avatar'
    for c in ['ava','ethan','sofia','diego']:
        m,hero=setup(c,fdir);mst=verify.analyse(hero)
        p0=cv2.imread(f'{fdir}/{c}/gaze.jpg');print(c,'prod',np.round(gate_eye(c,hero,m,p0,mst),2))
        for k in (0.4,0.7,1.0):
            for only in (None,(0,),(1,)):
                new,m,hero=run_k(c,fdir,k,only=only);print('  k',k,'only',only,np.round(gate_eye(c,hero,m,new,mst),2))
