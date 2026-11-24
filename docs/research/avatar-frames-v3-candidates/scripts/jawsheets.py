from jaw import *
import sys
def label(im,t):
    im=im.copy();cv2.putText(im,t,(4,14),cv2.FONT_HERSHEY_SIMPLEX,0.45,(255,255,255),2);cv2.putText(im,t,(4,14),cv2.FONT_HERSHEY_SIMPLEX,0.45,(0,0,0),1);return im
FR=['a','a2','l','o']
def run(tag=''):
    for c in ['ava','ethan','sofia','diego']:
        m=man(c);hero=cv2.resize(cv2.imread(R+f'assets/coaches/{c}-hero.jpg'),(m['width'],m['height']),interpolation=cv2.INTER_AREA)
        x,y,w,h=m['frames']['a']['rect'];rows=[];bd=0
        for n in FR:
            for base,nm in ((R+f'assets/avatar/{c}/','prod'),(OUT+f'{c}/','cand')):
                p=cv2.imread(base+n+'.jpg');tiles=[]
                for j in (0,0.5,1.0):
                    im=composite(c,hero,p,j)
                    if nm=='cand':
                        d=np.abs(im[y:y+h,x:x+w].astype(int)-hero[y:y+h,x:x+w].astype(int)).max(2)
                        ring=np.zeros_like(d,bool);ring[:2]=1;ring[-2:]=1;ring[:,:2]=1;ring[:,-2:]=1
                        bd=max(bd,int(d[ring].max()))
                    tiles.append(label(im[y+50:y+270,x+80:x+370],f'{c} {n} {nm} jaw{j}'))
                rows.append(np.hstack(tiles))
        cv2.imwrite(OUT+f'{c}/contact-jaw{tag}.jpg',np.vstack(rows),[cv2.IMWRITE_JPEG_QUALITY,88]);print(c,'max border diff vs portrait (cand, jaw 0/.5/1):',bd)
run()
