from gazesyn import *
fdir='/home/user/datewiseaiapp/assets/avatar';OUTD='/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad/avatar-frames-v3/'
SH={'ava':(5,0),'ethan':(5,0),'sofia':(-6,0),'diego':(5,0)}
for c,sh in SH.items():
    o,R,_=synth(c,fdir,shift=sh);cv2.imwrite(OUTD+f'{c}/gaze.jpg',o,[cv2.IMWRITE_JPEG_QUALITY,92])
