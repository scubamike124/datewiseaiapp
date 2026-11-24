from eyesweep import *
from lid import half_blink
import json
fdir='/home/user/datewiseaiapp/assets/avatar';OUTD='/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad/avatar-frames-v3/'
rep={}
# gaze: Ethan and Diego, image-left eye only, iris correction toward the portrait (production kept where the gate did not improve)
for c,only in [('ethan',(0,)),('diego',(0,))]:
    m,hero=setup(c,fdir);mst=verify.analyse(hero);p0=cv2.imread(f'{fdir}/{c}/gaze.jpg')
    new,m,hero=run_k(c,fdir,1.0,only=only)
    cv2.imwrite(OUTD+f'{c}/gaze.jpg',new,[cv2.IMWRITE_JPEG_QUALITY,92])
    # re-read to measure the JPEG as shipped
    sh=cv2.imread(OUTD+f'{c}/gaze.jpg');rep[c]=dict(before=gate_eye(c,hero,m,p0,mst),after=gate_eye(c,hero,m,sh,mst))
for c,eyes,t in [('ava',(0,),0.5),('diego',(1,),0.62)]:
    o,R,C,dbg=half_blink(c,fdir,t=t,eyes=eyes,base='prod')
    cv2.imwrite(OUTD+f'{c}/blink_half.jpg',o,[cv2.IMWRITE_JPEG_QUALITY,90])
print(json.dumps(rep,indent=1))
