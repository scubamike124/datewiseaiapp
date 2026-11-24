import os,sys,json
S='/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad/'
os.environ['AVATAR_TOOLS']=S+'ondevice-qa/tools'
sys.path.insert(0,'/home/user/datewiseaiapp/tool/avatar')
import verify,cv2,numpy as np
R='/home/user/datewiseaiapp/'
def per_eye(img,face):
    iod=float(np.hypot(face[6]-face[4],face[7]-face[5]));r=max(3,int(0.10*iod));out=[]
    for ex,ey in [(face[4],face[5]),(face[6],face[7])]:
        p=img[max(0,int(ey)-r):int(ey)+r,max(0,int(ex)-r):int(ex)+r]
        lab=cv2.cvtColor(p,cv2.COLOR_BGR2LAB).reshape(-1,3).astype(float);lab[:,0]*=100/255.;lab[:,1:]-=128
        lo,hi=np.percentile(lab[:,0],[10,50]);d=lab[(lab[:,0]>=lo)&(lab[:,0]<=hi)];out.append(d.mean(0))
    return out
def setup(c,fdir):
    m=json.load(open(R+f'assets/avatar/{c}/manifest.json'))
    hero=cv2.resize(cv2.imread(R+f'assets/coaches/{c}-hero.jpg'),(m['width'],m['height']),interpolation=cv2.INTER_AREA)
    return m,hero
def comp(hero,m,fdir,c,n):
    x,y,w,h=m['frames'][n]['rect'];im=hero.copy();im[y:y+h,x:x+w]=cv2.imread(f'{fdir}/{c}/{n}.jpg');return im
if __name__=='__main__':
    fdir=sys.argv[1]
    for c in ['ava','ethan','sofia','diego']:
        m,hero=setup(c,fdir);mst=verify.analyse(hero);pm=per_eye(hero,mst['face'])
        print(c,'portrait L,a,b  eyeL',np.round(pm[0],1),'eyeR',np.round(pm[1],1),'(eye indices: 4,5 = image-left eye? )')
        for n in ['gaze','blink_half','blink_closed']:
            im=comp(hero,m,fdir,c,n);a=verify.analyse(im)
            pts=a['face'] if n=='gaze' else mst['face']
            pe=per_eye(im,pts)
            d=[float(np.hypot(pe[i][1]-pm[i][1],pe[i][2]-pm[i][2])) for i in (0,1)];dl=[float(abs(pe[i][0]-pm[i][0])) for i in (0,1)]
            print(' ',n,'L',[np.round(p,1).tolist() for p in pe],'dab',np.round(d,1),'dL',np.round(dl,1))
