from paint import *
P={'a':(8,False),'a2':(5,False),'l':(1,True)}
for c in ['ava','ethan','sofia','diego']:
    for n,(D,tu) in P.items():
        o,g=paint_open(c,n,D,tu)
        cv2.imwrite(OUT+f'{c}/{n}.jpg',o,[cv2.IMWRITE_JPEG_QUALITY,88])
print('done')
