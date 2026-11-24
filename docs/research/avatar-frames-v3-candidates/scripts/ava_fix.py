from lib import *
def fix_blotch(img,box=(185,270,160,310)):
    y0,y1,x0,x1=box;L=lab(img);sub=L[y0:y1,x0:x1]
    hot=((sub[...,1]>35.5)|(sub[...,2]>24.5)).astype(np.float32)
    hot=cv2.GaussianBlur(cv2.dilate(hot,np.ones((7,7),np.uint8)),(0,0),4)
    # smooth reference of lip chroma: blur of clipped chroma
    a=np.minimum(sub[...,1],34.0);b=np.minimum(sub[...,2],21.5)
    a=cv2.GaussianBlur(a,(0,0),5);b=cv2.GaussianBlur(b,(0,0),5)
    s2=sub.copy();s2[...,1]=sub[...,1]*(1-hot)+np.minimum(sub[...,1],a)*hot
    s2[...,2]=sub[...,2]*(1-hot)+np.minimum(sub[...,2],b)*hot
    L2=L.copy();L2[y0:y1,x0:x1]=s2;return unlab(L2),hot.max()
if __name__=='__main__':
    o=cv2.imread(OUT+'ava/a.jpg');n,h=fix_blotch(o);print(h)
    cv2.imwrite('t11.jpg',cv2.resize(np.hstack([o,n])[150:327,60:850+200],None,fx=1.4,fy=1.4))
