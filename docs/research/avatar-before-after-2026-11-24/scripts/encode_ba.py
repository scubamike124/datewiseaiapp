import json, subprocess, sys, glob
import numpy as np
from PIL import Image, ImageDraw, ImageFont
S='/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad'
QA=f'{S}/ondevice-qa'; W=f'{S}/before-after/work'; OUT=f'{S}/before-after'
name=sys.argv[1]
job=json.load(open(f'{QA}/jobs/{name}.json'))
lb=json.load(open(f'{W}/before/{name}.log.json')); la=json.load(open(f'{W}/after/{name}.log.json'))
fb=sorted(glob.glob(f'{W}/before/{name}/f*.png')); fa=sorted(glob.glob(f'{W}/after/{name}/f*.png'))
assert len(fb)==len(fa)==len(lb['frames'])==len(la['frames'])==450,(len(fb),len(fa))
B=lambda s,z:ImageFont.truetype(f'/usr/share/fonts/truetype/dejavu/DejaVuSans{"-Bold" if s else ""}.ttf',z)
fT,fL,fS,fC=B(1,30),B(1,34),B(0,22),B(1,44)
w=Image.open(fb[0]).size[0]; hb=Image.open(fb[0]).size[1]; ha=Image.open(fa[0]).size[1]
G=24; TOP=150; LAB=56; STAGE_H=max(hb,ha); BOT=170
CW=2*w+3*G; CH=TOP+LAB+STAGE_H+BOT; CH+=CH%2
surf=tuple(Image.open(fa[0]).convert('RGB').getpixel((5,ha-1)))
bg=(12,12,12)
voice=job['voice_of']; coach=job['coach']
src=f"{coach.capitalize()}'s own recording" if voice==coach else f"CROSS-LANGUAGE TEST AUDIO: {voice.capitalize()}'s recording ({job['language']}) used for {coach.capitalize()}"
colors={'listening':(120,200,255),'thinking':(255,200,90),'speaking':(120,230,140),'idle':(180,180,180)}
cap={'listening':'LISTENING (user is talking)','thinking':'THINKING','speaking':'SPEAKING','idle':'IDLE'}
out=f'{OUT}/{name.split("-")[0]}-{name.split("-")[1]}-before-after.mp4'
cmd=['ffmpeg','-y','-loglevel','error','-f','rawvideo','-pix_fmt','rgb24','-s',f'{CW}x{CH}','-r','30','-i','-','-i',job['wav'],'-map','0:v','-map','1:a','-c:v','libx264','-crf','18','-preset','medium','-pix_fmt','yuv420p','-c:a','aac','-b:a','128k','-shortest',out]
p=subprocess.Popen(cmd,stdin=subprocess.PIPE)
base=Image.new('RGB',(CW,CH),bg); d=ImageDraw.Draw(base)
d.rectangle([0,0,CW,64],fill=(120,20,20))
d.text((G,14),"SIMULATION - not a device recording. Host render of the app's own avatar code (AvatarFrames, AvatarAnimator, LipSyncDriver on loudness, AvatarPainter).",font=fS,fill=(255,255,255))
d.text((G,76),f"{coach.capitalize()}  |  {'English' if job['language']=='en' else 'Mexican Spanish'}  |  iPhone 15 stage 369 pt wide at 3x  |  audio: {src}",font=fS,fill=(255,170,170) if voice!=coach else (200,200,200))
d.text((G,108),"Same audio, timeline and animation seed on both sides.",font=fS,fill=(150,150,150))
xs=[G,2*G+w]
labs=[("BEFORE: today's PR branch (dd3eac5)",f"old frames, old animation, old framing, stage {hb/3:.0f} pt tall"),("AFTER: candidate",f"new mouth frames + gaze/blink fix (26396da) + framing (8d5753c), stage {ha/3:.0f} pt tall")]
for x,(a,b) in zip(xs,labs):
    d.text((x,TOP-8),a,font=fT,fill=(255,255,255)); d.text((x,TOP+28),b,font=fS,fill=(170,170,170))
y0=TOP+LAB
for x,hh in zip(xs,(hb,ha)):
    d.rectangle([x,y0,x+w-1,y0+STAGE_H-1],fill=surf)
    d.rectangle([x-1,y0-1,x+w,y0+hh],outline=(90,90,90))
for i,(a,b,ra,rb) in enumerate(zip(fb,fa,lb['frames'],la['frames'])):
    c=base.copy(); d=ImageDraw.Draw(c)
    c.paste(Image.open(a).convert('RGB'),(xs[0],y0)); c.paste(Image.open(b).convert('RGB'),(xs[1],y0))
    yy=y0+STAGE_H+14
    for x,r in zip(xs,(ra,rb)):
        d.text((x,yy),cap[r['mood']],font=fC,fill=colors[r['mood']])
        lay=','.join(l.split('@')[0] for l in r['layers']) or '-'
        d.text((x,yy+58),f"mouth={r['mouth']}  jaw={r['jaw']:.2f}  patches={lay}",font=fS,fill=(200,200,200))
    d.text((G,yy+112),f"t = {ra['t']:5.2f} s / 15.00 s",font=fS,fill=(150,150,150))
    # progress bar
    d.rectangle([G,CH-14,CW-G,CH-8],fill=(40,40,40)); d.rectangle([G,CH-14,G+int((CW-2*G)*i/449),CH-8],fill=(200,200,200))
    p.stdin.write(np.asarray(c).tobytes())
p.stdin.close(); p.wait(); print(out)
