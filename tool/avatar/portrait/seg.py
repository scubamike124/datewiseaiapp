import os
# MediaPipe selfie multiclass segmenter (Apache-2.0): 0 background, 1 hair, 2 body skin, 3 face skin, 4 clothes, 5 others (accessories)
import numpy as np, cv2, mediapipe as mp
from mediapipe.tasks.python import vision, BaseOptions
M=os.path.join(os.environ.get('DW_PORTRAIT_WORK', os.path.expanduser('~/dw-portrait-work')), 'fp/models/mc.tflite')
_s=None
def segment(bgr):
    """Returns float32 HxWx6 class probabilities at the image size."""
    global _s
    if _s is None:
        _s=vision.ImageSegmenter.create_from_options(vision.ImageSegmenterOptions(base_options=BaseOptions(model_asset_path=M),output_confidence_masks=True,output_category_mask=False))
    rgb=cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB)
    r=_s.segment(mp.Image(image_format=mp.ImageFormat.SRGB,data=np.ascontiguousarray(rgb)))
    ms=[m.numpy_view().astype(np.float32) for m in r.confidence_masks]
    H,W=bgr.shape[:2]
    return np.stack([cv2.resize(m,(W,H),interpolation=cv2.INTER_LINEAR) for m in ms],-1)
def viz(bgr,p):
    cols=np.array([[40,40,40],[0,200,255],[255,0,255],[0,255,0],[255,128,0],[0,0,255]],np.float32)
    lab=cols[p.argmax(-1)]
    return (0.5*bgr+0.5*lab).astype(np.uint8)
