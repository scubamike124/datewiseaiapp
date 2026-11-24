import sys, cv2, numpy as np, mediapipe as mp, colorsys
from mediapipe.tasks import python as mpt
from mediapipe.tasks.python import vision
S='/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad'
det = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(base_options=mpt.BaseOptions(model_asset_path=f'{S}/face_landmarker.task'), num_faces=1))
def iris(rgb):
    h,w=rgb.shape[:2]; r=det.detect(mp.Image(image_format=mp.ImageFormat.SRGB,data=np.ascontiguousarray(rgb)))
    l=np.array([[p.x*w,p.y*h] for p in r.face_landmarks[0]]); out=[]
    for c,e in ((468,469),(473,474)):
        rad=np.linalg.norm(l[c]-l[e])*0.75; yy,xx=np.mgrid[:h,:w]; m=(xx-l[c][0])**2+(yy-l[c][1])**2<rad**2
        px=rgb[m].astype(float); v=px.mean(1); px=px[(v>25)&(v<200)]; out.append(px.mean(0))
    rgbm=np.mean(out,0); hh,ss,vv=colorsys.rgb_to_hsv(*(rgbm/255)); return rgbm.round(0), round(hh*360), round(ss,2), round(vv,2)
print('ref', iris(cv2.cvtColor(cv2.imread(sys.argv[1]),cv2.COLOR_BGR2RGB)))
cap=cv2.VideoCapture(sys.argv[2]); i=0; res=[]
while True:
    ok,f=cap.read()
    if not ok: break
    if i%25==0:
        try: res.append(iris(cv2.cvtColor(f,cv2.COLOR_BGR2RGB)))
        except Exception as e: pass
    i+=1
print('video mean RGB', np.mean([r[0] for r in res],0).round(0), 'hue range', min(r[1] for r in res), max(r[1] for r in res), 'sat', np.mean([r[2] for r in res]).round(2))
