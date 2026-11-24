from lib import *
CH={'ava':['a','a2','l','o','o2','blink_half','gaze'],'ethan':['a','a2','l','o','o2','gaze'],'sofia':['a','a2','l','i2','sh','gaze'],'diego':['a','a2','l','blink_half','gaze']}
def label(im,t):
    im=im.copy();cv2.putText(im,t,(4,14),cv2.FONT_HERSHEY_SIMPLEX,0.45,(255,255,255),2);cv2.putText(im,t,(4,14),cv2.FONT_HERSHEY_SIMPLEX,0.45,(0,0,0),1);return im
def wrap(tiles,W=1800):
    rows=[];cur=[];w=0
    for t in tiles:
        if w+t.shape[1]>W and cur: rows.append(cur);cur=[];w=0
        cur.append(t);w+=t.shape[1]
    rows.append(cur);H=[max(t.shape[0] for t in r) for r in rows]
    out=[]
    for r,h in zip(rows,H):
        r=[cv2.copyMakeBorder(t,0,h-t.shape[0],0,0,cv2.BORDER_CONSTANT) for t in r];row=np.hstack(r)
        out.append(cv2.copyMakeBorder(row,0,0,0,W-row.shape[1],cv2.BORDER_CONSTANT))
    return np.vstack(out)
for c in CH:
    m=man(c);hero=cv2.resize(cv2.imread(R+f'assets/coaches/{c}-hero.jpg'),(m['width'],m['height']),interpolation=cv2.INTER_AREA)
    for tag in ('full','phone'):
        sheets=[]
        for title,base in (('BEFORE (approved)',R+f'assets/avatar/{c}/'),('AFTER (candidate)',OUT+f'{c}/')):
            tiles=[]
            for n in CH[c]:
                x,y,w,h=m['frames'][n]['rect'];im=hero.copy();im[y:y+h,x:x+w]=cv2.imread(base+n+'.jpg')
                if n in('blink_half','blink_closed','gaze'): box=(y,y+h,x,x+w)
                else: box=(y+50,y+250,x+90,x+380)
                cr=im[box[0]:box[1],box[2]:box[3]]
                if tag=='phone':
                    s=780/1080.;cr=cv2.resize(cr,None,fx=s,fy=s,interpolation=cv2.INTER_AREA)
                tiles.append(label(cr,n))
            hd=label(np.zeros((22,1800,3),np.uint8),title);sheets+=[hd,wrap(tiles)]
        cv2.imwrite(OUT+f'{c}/contact-{tag}.jpg',np.vstack(sheets),[cv2.IMWRITE_JPEG_QUALITY,90])
