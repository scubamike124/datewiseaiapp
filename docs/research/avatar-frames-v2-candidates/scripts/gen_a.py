from ov import *;from tones import TONE
PARAMS={'a':(15,True,False),'a2':(11,True,False),'l':(9,True,True)}
for c in ['ava','ethan','sofia','diego']:
    for n,(D,tg,tu) in PARAMS.items():
        o=open_vowel(c,n,D,TONE[c],tongue=tg,tongue_up=tu)
        cv2.imwrite(OUT+f'{c}/{n}.jpg',o,[cv2.IMWRITE_JPEG_QUALITY,88])
