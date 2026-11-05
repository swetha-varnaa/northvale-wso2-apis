import json,sys
o=json.load(open(sys.argv[1]))
for k,f in o.items():
    r=f.get('result',f); fm=r.get('flowModel') if isinstance(r,dict) else None
    if not fm: print(k,'ERROR',json.dumps(r)[:300]); continue
    cnt={}
    def walk(nodes,d=0):
        for n in nodes:
            kind=n.get('codedata',{}).get('node','?'); cnt[kind]=cnt.get(kind,0)+1
            if d<=int(sys.argv[2]): print('  '*d+kind,'|',((n.get('metadata') or {}).get('label') or '')[:50])
            for b in n.get('branches',[]) or []:
                if d<=int(sys.argv[2]): print('  '*(d+1)+'['+str(b.get('label',''))+']')
                walk(b.get('children',[]),d+2)
    walk(fm.get('nodes',[])); print('COUNTS',cnt)
