import sys, numpy as np, mediapipe as mp
from PIL import Image
from mediapipe.tasks.python import vision, BaseOptions as B
arr=np.array(Image.open(sys.argv[1]).convert("RGB")); h,w=arr.shape[:2]
d=vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(base_options=B(model_asset_path=sys.argv[2]),num_faces=1))
r=d.detect(mp.Image(image_format=mp.ImageFormat.SRGB,data=arr)); p=np.array([[q.x*w,q.y*h] for q in r.face_landmarks[0]])
print(p.min(0),p.max(0))
