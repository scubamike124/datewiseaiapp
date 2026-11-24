import math
NET15=19.99*0.85*0.97; NET30=19.99*0.70*0.97
TEXT={'light':0.065,'typical':0.326,'heavy':2.324}   # AI_COST_MODEL.md s5, 1000 subs, Llama 3.3
MIN={'light':20,'typical':60,'heavy':150}
D=0.5   # speaking duty cycle
print(f"NET15={NET15:.2f} NET30={NET30:.2f}")
# self-hosted candidates: (name, gpu, $/h, speaking streams per GPU, hybrid?)
SH=[
 ('a MuseTalk1.5+LiveTalking, 4090 RunPod community',0.34,2,True),
 ('a MuseTalk1.5+LiveTalking, 4090 RunPod secure',0.89,2,True),
 ('a MuseTalk1.5+LiveTalking, 4090 RunPod serverless',1.34,2,True),
 ('a MuseTalk1.5, L4 AWS g6 on-demand',0.8048,1,True),
 ('b FlashHead Lite+Mynah, 4090 secure, 1 stream (Mynah measured)',0.89,1,True),
 ('b FlashHead Lite+Mynah, 4090 secure, 3 streams (Soul claim)',0.89,3,True),
 ('b FlashHead Lite+OAC (GPU busy idle), 4090 secure, 1 stream',0.89,1,False),
 ('c FlashHead Pro, 2x5090 Vast median on-demand, 1 stream',1.35,1,True),
 ('c FlashHead Pro, H100 SXM RunPod community, 1 stream [est]',2.69,1,True),
]
print("\n## self-hosted per-minute and per-subscriber (u = utilisation of provisioned slots)")
for n,p,s,h in SH:
    spk=p/60/s
    dc = D if h else 1.0
    for u in (1.0,0.5):
        wall=spk*dc/u
        row=[f"{n}",f"$/h={p}",f"streams={s}",f"$/speak-min={spk:.4f}",f"u={u}",f"$/wall-min={wall:.4f}"]
        for k in MIN:
            av=wall*MIN[k]; tot=av+TEXT[k]
            row.append(f"{k}: av ${av:.2f} tot ${tot:.2f} m15 {(NET15-tot)/NET15*100:.1f}% m30 {(NET30-tot)/NET30*100:.1f}%")
        print(" | ".join(row))
HO=[('bitHuman cloud',0.04,1),('bitHuman on-device (speaking only)',0.02,D),('Simli Hobby',0.01,1),('Simli Scale',0.009,1),
    ('Anam Starter',0.16,1),('Anam Pro',0.11,1),('Anam enterprise floor',0.04,1),('LiveAvatar LITE Essential overage',0.095,1),('LiveAvatar LITE Business incl.',0.0792,1),
    ('LiveAvatar FULL Essential overage',0.19,1),('Tavus Builder',0.35,1),('Tavus Business',0.26,1)]
print("\n## hosted")
for n,r,f in HO:
    row=[n,f"$/wall-min={r*f:.4f}",f"$/h={r*f*60:.2f}"]
    for k in MIN:
        av=r*f*MIN[k]; tot=av+TEXT[k]
        row.append(f"{k}: av ${av:.2f} tot ${tot:.2f} m15 {(NET15-tot)/NET15*100:.1f}% m30 {(NET30-tot)/NET30*100:.1f}%")
    print(" | ".join(row))

def binq(n,p,q):
    c=0.0
    for k in range(n+1):
        c+=math.comb(n,k)*p**k*(1-p)**(n-k)
        if c>=q: return k
print("\n## capacity")
PAR=3; HRS=730
for S in (10,100,1000):
    slots_h=binq(S,D,0.995); slots_a=S
    print(f"S={S} hybrid slots(99.5%)={slots_h} saving={(1-slots_h/S)*100:.0f}%  subs supported typical(60min,PAR3)={S*43200/(60*PAR):.0f} light={S*43200/(20*PAR):.0f} heavy={S*43200/(150*PAR):.0f}")
    for n,p,s,h in [SH[0],SH[1],SH[2],SH[4],SH[6],SH[7]]:
        slots=slots_h if h else slots_a
        g=math.ceil(slots/s); spare=max(1,math.ceil(0.1*g)); peak=g+spare
        fixed=peak*p*HRS
        avg=max(1+ (1 if S>=100 else 0), peak/PAR*1.2)
        auto=avg*p*HRS
        subs=S*43200/(60*PAR)
        print(f"   {n}: GPUs peak={peak} (={g}+{spare} spare) fixed24/7=${fixed:,.0f}/mo  autoscaled avgGPUs={avg:.1f} ${auto:,.0f}/mo  $/typical-sub fixed={fixed/subs:.2f} auto={auto/subs:.2f}")
    tot_min=S/PAR*43200
    for n,r,f in HO:
        print(f"   hosted {n}: minutes/mo={tot_min:,.0f} ${tot_min*r*f:,.0f}/mo  $/typical-sub={tot_min*r*f/(S*43200/(60*PAR)):.2f}")
# break-even self-host floor vs Simli
for fl,lab in ((0.34*730,'community 4090'),(0.89*730,'secure 4090')):
    for k in MIN: print(f"break-even {lab} floor ${fl:.0f} vs Simli $0.01: {k} {fl/(0.01*MIN[k]):.0f} subs")
# avatar budget at 70% margin
for net,lab in ((NET15,'15%'),(NET30,'30%')):
    b=net*0.30
    for k in MIN:
        ab=b-TEXT[k]
        print(f"70% margin {lab}: max AI+infra ${b:.2f}; avatar budget {k} ${ab:.2f}: Simli {ab/0.01:.0f} min, bitHuman cloud {ab/0.04:.0f}, Anam Pro {ab/0.11:.0f}, LiveAvatar LITE {ab/0.095:.0f}, Tavus Bus {ab/0.26:.0f}, MuseTalk secure u0.5 {ab/(0.89/60/2*0.5/0.5):.0f}")
