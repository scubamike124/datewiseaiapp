"""LivePortrait (MIT code + MIT weights) driven without InsightFace.

InsightFace's pretrained detector/landmark models are non-commercial, so this
engine replaces them with OpenCV YuNet (MIT) for the face box + 5 points, then
uses LivePortrait's own 203-point landmark model (landmark.onnx, MIT, part of
the LivePortrait weights) for the crop and the eye/lip ratios.

Expression edits are applied to the implicit keypoints exactly as LivePortrait's
own image-retargeting tool does (src/gradio_pipeline.py), CPU only.
"""
import os, sys, numpy as np, cv2, torch

TOOLS = os.environ.get("AVATAR_TOOLS", os.path.expanduser("~/.cache/datewise-avatar-tools"))
LP = os.path.join(TOOLS, "LivePortrait")
sys.path.insert(0, LP)

from src.config.inference_config import InferenceConfig  # noqa: E402
from src.live_portrait_wrapper import LivePortraitWrapper  # noqa: E402
from src.utils.human_landmark_runner import LandmarkRunner  # noqa: E402
from src.utils.crop import crop_image, prepare_paste_back, paste_back  # noqa: E402
from src.utils.camera import get_rotation_matrix  # noqa: E402
from src.utils.retargeting_utils import calc_eye_close_ratio, calc_lip_close_ratio  # noqa: E402

YUNET = os.path.join(TOOLS, "models", "yunet.onnx")
torch.set_num_threads(max(1, os.cpu_count() or 4))


def yunet_5pt(img_bgr):
    h, w = img_bgr.shape[:2]
    det = cv2.FaceDetectorYN.create(YUNET, "", (w, h), 0.8, 0.3, 5000)
    _, f = det.detect(img_bgr)
    if f is None or len(f) == 0:
        raise RuntimeError("no face found")
    f = max(f, key=lambda x: x[2] * x[3])
    # YuNet order: right eye (image left), left eye, nose, right mouth corner, left mouth corner
    return f[4:14].reshape(5, 2).astype(np.float32), f


class Engine:
    def __init__(self, crop_scale=2.3):
        cfg = InferenceConfig()
        cfg.flag_force_cpu = True
        cfg.flag_use_half_precision = False
        self.cfg = cfg
        self.w = LivePortraitWrapper(inference_cfg=cfg)
        self.lmk = LandmarkRunner(ckpt_path=os.path.join(LP, "pretrained_weights/liveportrait/landmark.onnx"), onnx_provider="cpu")
        self.crop_scale = crop_scale

    @torch.no_grad()
    def prepare(self, img_rgb):
        pt5, face = yunet_5pt(cv2.cvtColor(img_rgb, cv2.COLOR_RGB2BGR))
        lmk203 = self.lmk.run(img_rgb, pt5)
        lmk203 = self.lmk.run(img_rgb, lmk203)  # refine once on its own crop
        crop = crop_image(img_rgb, lmk203, dsize=512, scale=self.crop_scale, vy_ratio=-0.125, flag_do_rot=True)
        img256 = cv2.resize(crop["img_crop"], (256, 256), interpolation=cv2.INTER_AREA)
        lmk_crop = self.lmk.run(img_rgb, lmk203)
        I_s = self.w.prepare_source(img256)
        info = self.w.get_kp_info(I_s)
        st = dict(
            img=img_rgb, face=face, lmk203=lmk203, M_c2o=crop["M_c2o"],
            mask=prepare_paste_back(self.cfg.mask_crop, crop["M_c2o"], dsize=(img_rgb.shape[1], img_rgb.shape[0])),
            info=info, f_s=self.w.extract_feature_3d(I_s), x_s=self.w.transform_keypoint(info),
            R_s=get_rotation_matrix(info["pitch"], info["yaw"], info["roll"]),
            lmk_src=lmk_crop,
            eye_ratio=float(calc_eye_close_ratio(lmk_crop[None]).mean()),
            lip_ratio=float(calc_lip_close_ratio(lmk_crop[None])[0][0]),
        )
        return st

    @torch.no_grad()
    def render(self, st, eye=None, lip=None, pitch=0.0, yaw=0.0, roll=0.0, smile=0.0, pout=0.0, purse=0.0,
               grin=0.0, open3=0.0, brow=0.0, gaze_x=0.0, gaze_y=0.0):
        info = st["info"]
        R_d = get_rotation_matrix(info["pitch"] + pitch, info["yaw"] + yaw, info["roll"] + roll)
        R_s = st["R_s"]
        R_new = (R_d @ R_s.permute(0, 2, 1)) @ R_s
        d = info["exp"].clone()
        # The same keypoint edits as LivePortrait's retargeting sliders.
        if gaze_x or gaze_y:
            if gaze_x > 0:
                d[0, 11, 0] += gaze_x * 0.0007; d[0, 15, 0] += gaze_x * 0.001
            else:
                d[0, 11, 0] += gaze_x * 0.001; d[0, 15, 0] += gaze_x * 0.0007
            d[0, 11, 1] += gaze_y * -0.001; d[0, 15, 1] += gaze_y * -0.001
            b = -gaze_y / 2.
            d[0, 11, 1] += b * -0.001; d[0, 13, 1] += b * 0.0003; d[0, 15, 1] += b * -0.001; d[0, 16, 1] += b * 0.0003
        if smile:
            d[0, 20, 1] += smile * -0.01; d[0, 14, 1] += smile * -0.02; d[0, 17, 1] += smile * 0.0065
            d[0, 17, 2] += smile * 0.003; d[0, 13, 1] += smile * -0.00275; d[0, 16, 1] += smile * -0.00275
            d[0, 3, 1] += smile * -0.0035; d[0, 7, 1] += smile * -0.0035
        if brow:
            if brow > 0:
                d[0, 1, 1] += brow * 0.001; d[0, 2, 1] += brow * -0.001
            else:
                d[0, 1, 0] += brow * -0.001; d[0, 2, 0] += brow * 0.001
                d[0, 1, 1] += brow * 0.0003; d[0, 2, 1] += brow * -0.0003
        if pout:
            d[0, 19, 0] += pout
        if purse:
            d[0, 14, 1] += purse * 0.001; d[0, 3, 1] += purse * -0.0005; d[0, 7, 1] += purse * -0.0005
            d[0, 17, 2] += purse * -0.0005
        if grin:
            d[0, 20, 2] += grin * -0.001; d[0, 20, 1] += grin * -0.001; d[0, 14, 1] += grin * -0.001
        if open3:
            d[0, 19, 1] += open3 * 0.001; d[0, 19, 2] += open3 * 0.0001; d[0, 17, 1] += open3 * -0.0001
        x_d = info["scale"] * (info["kp"] @ R_new + d) + info["t"]
        x_s = st["x_s"]
        if eye is not None:
            x_d = x_d + self.w.retarget_eye(x_s, self.w.calc_combined_eye_ratio([[float(eye)]], st["lmk_src"]))
        if lip is not None:
            x_d = x_d + self.w.retarget_lip(x_s, self.w.calc_combined_lip_ratio([[float(lip)]], st["lmk_src"]))
        x_d = self.w.stitching(x_s, x_d)
        out = self.w.warp_decode(st["f_s"], x_s, x_d)
        crop = self.w.parse_output(out["out"])[0]
        return crop, paste_back(crop, st["M_c2o"], st["img"], st["mask"])
