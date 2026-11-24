from lib import *
import math
JAWDROP=0.12
def jaw_patch(c,patch,jaw,rect=None):
    """exact port of AvatarPainter._drawJaw (portrait-space, scale 1): triangle mesh 8x12, bilinear-textured"""
    m=man(c);x0,y0,w,h=m['frames']['a']['rect'] if rect is None else rect
    mouthY=m['mouth'][1];mw=m['mouth_width']
    lineV=min(max((mouthY-y0)/h,0.1),0.7);peakV=min(max((mouthY+0.45*mw-y0)/h,lineV+0.08),0.88)
    drop=jaw*JAWDROP*mw
    def sm(x): return x*x*(3-2*x)
    def wy(v):
        if v<=lineV: return 0
        if v<=peakV: return sm((v-lineV)/(peakV-lineV))
        return sm((1-v)/(1-peakV))
    nx,ny=8,12;out=np.zeros((h,w,3),np.float32);cov=np.zeros((h,w),np.float32)
    def pos(i,j):
        u=i/nx;v=j/ny;return (u*w,v*h+drop*math.sin(math.pi*u)*wy(v))
    def tex(i,j): return (i/nx*w,j/ny*h)
    # inverse mapping per triangle via affine transform on a canvas; accumulate onto a big canvas then crop
    pad=int(drop)+4;canvas=np.zeros((h+pad,w,3),np.uint8);mask=np.zeros((h+pad,w),np.uint8)
    for j in range(ny):
        for i in range(nx):
            for tri in (((0,0),(1,0),(1,1)),((0,0),(1,1),(0,1))):
                src=np.float32([tex(i+a,j+b) for a,b in tri]);dst=np.float32([pos(i+a,j+b) for a,b in tri])
                M=cv2.getAffineTransform(src,dst)
                wp=cv2.warpAffine(patch,M,(w,h+pad),flags=cv2.INTER_LINEAR,borderMode=cv2.BORDER_REFLECT)
                tm=np.zeros((h+pad,w),np.uint8);cv2.fillConvexPoly(tm,np.int32(np.round(dst)),1)
                canvas[tm>0]=wp[tm>0];mask[tm>0]=1
    return canvas[:h],mask[:h]
def composite(c,hero,patch,jaw,rect=None):
    m=man(c);x,y,w,h=m['frames']['a']['rect'] if rect is None else rect
    im=hero.copy()
    if jaw<0.01: im[y:y+h,x:x+w]=patch;return im
    cv_,mk=jaw_patch(c,patch,jaw,rect)
    reg=im[y:y+h,x:x+w];reg[mk>0]=cv_[mk>0];return im
