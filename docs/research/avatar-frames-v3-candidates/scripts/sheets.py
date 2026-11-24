from lib import *
CH={'ava':['a','a2','l','o','o2','blink_half','gaze'],'ethan':['a','a2','l','o','o2','gaze'],'sofia':['a','a2','l','i2','sh'],'diego':['a','a2','l','blink_half','gaze']}
def label(im,t):
    im=im.copy();cv2.putText(im,t,(4,14),cv2.FONT_HERSHEY_SIMPLEX,0.45,(255,255,255),2);cv2.putText(im,t,(4,14),cv2.FONT_HERSHEY_SIMPLEX,0.45,(0,0,0),1);return im
for c in CH:
    m=man(c);hero=cv2.resize(cv2.imread(R+f'assets/coaches/{c}-hero.jpg'),(m['width'],m['height']),interpolation=cv2.INTER_AREA)
    x,y,w,h=m['frames']['a']['rect']
    def comp(path):
        im=hero.copy();im[y:y+h,x:x+w]=cv2.imread(path);return im
    for tag,scale,crop in [('full',1.0,(y+50,y+250,x+90,x+380)),('phone',780/1080,None)]:
        B=[];A=[]
        for n in CH[c]:
            for lst,p in [(B,R+f'assets/avatar/{c}/{n}.jpg'),(A,OUT+f'{c}/{n}.jpg')]:
                im=comp(p)
                if tag=='phone':
                    im=cv2.resize(im,None,fx=scale,fy=scale,interpolation=cv2.INTER_AREA)
                    s=scale;cr=im[int((y+60)*s):int((y+250)*s),int((x+60)*s):int((x+400)*s)]
                else: cr=im[crop[0]:crop[1],crop[2]:crop[3]]
                lst.append(label(cr,n))
        sw=min(len(CH[c]),4)
        def rows(L): return np.vstack([np.hstack(L[i:i+4]+[np.zeros_like(L[0])]*(4-len(L[i:i+4]))) for i in range(0,len(L),4)])
        sheet=np.vstack([label(np.zeros((22,B[0].shape[1]*4,3),np.uint8),'BEFORE (approved)'),rows(B),label(np.zeros((22,B[0].shape[1]*4,3),np.uint8),'AFTER (candidate)'),rows(A)])
        cv2.imwrite(OUT+f'{c}/contact-{tag}.jpg',sheet,[cv2.IMWRITE_JPEG_QUALITY,90])
