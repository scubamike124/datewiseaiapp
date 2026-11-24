from ov import *;from tones import TONE
def make_fv(c,D=8,hwf=0.19,tex_name='a'):
    f=frame(c,'fv');H,W=f.shape[:2];m=man(c);x0,y0r=m['frames']['a']['rect'][:2]
    mx=m['mouth'][0]-x0;my=m['mouth'][1]-y0r;mw=m['mouth_width']
    L=lab(f)[...,0];strip=L[int(my-14):int(my+14),int(mx-25):int(mx+25)].mean(1)
    strip=cv2.GaussianBlur(strip.reshape(-1,1),(0,0),1).ravel()
    yseam=int(my-14)+int(np.argmin(strip))
    # per-column seam (fit)
    ys=[];xs_=[]
    for x in range(int(mx-0.28*mw),int(mx+0.28*mw)):
        col=L[yseam-6:yseam+7,x-1:x+2].mean(1);ys.append(yseam-6+np.argmin(col));xs_.append(x)
    p=np.polyfit(xs_,ys,2);xs=np.arange(W,dtype=np.float32);yb=np.clip(np.polyval(p,xs),yseam-4,yseam+4).astype(np.float32)
    hw=hwf*mw
    tap=np.clip(1-((xs-mx)/hw)**2,0,1)**0.7;d=D*tap
    yy=np.arange(H,dtype=np.float32)[:,None];ybx=yb[None,:];dx=d[None,:]
    lr=0.25*mw;t=np.clip((yy-(ybx+dx))/lr,0,1);g=0.5*(1+np.cos(np.pi*t))
    srcy=np.where(yy<=ybx,yy,np.where(yy<=ybx+dx,ybx,yy-dx*g)).astype(np.float32)
    Wp=cv2.remap(f,np.tile(xs[None,:],(H,1)),srcy,cv2.INTER_CUBIC,borderMode=cv2.BORDER_REPLICATE)
    # teeth texture from the new open-vowel frame (upper incisors, lower edge)
    A=cv2.imread(OUT+f'{c}/{tex_name}.jpg');T,info=analyse(A,c);info['Lbright']=float(np.percentile(info['Lc'][T>0],85))
    yba=bite_curve(T,info,W).mean();cxa=info['cx']
    h_tex=D+6;tex=np.zeros((h_tex,W,3),np.uint8)
    # take rows ending at upper-teeth bottom edge: (yba-2.5) up
    src=A[int(yba-6-h_tex+1):int(yba-6)+1]
    sh=np.float32(0)
    # scale horizontally so teeth span ~ 1:1, centered at mx
    M=np.float32([[1,0,mx-cxa],[0,1,0]]);texw=cv2.warpAffine(src,M,(W,src.shape[0]),borderMode=cv2.BORDER_REPLICATE)
    tex=np.zeros_like(f);rows=np.arange(H)
    th=texw.shape[0]
    # place so tex bottom at lower edge of gap (ybx+dx+1): per column map
    ytexsrc=(yy-(ybx+dx+1)+th-1)
    texmap=cv2.remap(texw,np.tile(xs[None,:],(H,1)),np.clip(ytexsrc,0,th-1).astype(np.float32),cv2.INTER_LINEAR,borderMode=cv2.BORDER_REPLICATE)
    gap=((yy>=ybx-1)&(yy<=ybx+dx+1.5)&(dx>1.6)).astype(np.float32);gap=cv2.GaussianBlur(gap,(0,0),0.8)
    # teeth in the gap: darken toward the bottom (lip contact) and top (under upper lip)
    u=np.clip((yy-(ybx-1))/(dx+2.5),0,1)
    shade=1-0.10*np.exp(-(1-u)*6)-0.10*np.exp(-u*5)
    texmap=(texmap.astype(np.float32)*shade[...,None])
    out=Wp.astype(np.float32)*(1-gap[...,None])+texmap*gap[...,None]
    out=np.clip(out,0,255).astype(np.uint8)
    tone=dict(TONE[c]);alm=np.clip(gap,0,1)
    return teeth_detail(out,mx,mw*0.064,hash(c)%100,tone,depth=0.12,al=cv2.GaussianBlur((alm>0.5).astype(np.float32),(0,0),0.7))
if __name__=='__main__':
    rows=[]
    for c in ['ava','sofia']:
        o=make_fv(c);f=frame(c,'fv');cv2.imwrite(OUT+f'{c}/fv.jpg',o,[cv2.IMWRITE_JPEG_QUALITY,88])
        rows.append(cv2.resize(np.hstack([f,o])[90:230,100:350+450],None,fx=1.8,fy=1.8,interpolation=cv2.INTER_CUBIC))
    cv2.imwrite('t5.jpg',np.vstack(rows))
