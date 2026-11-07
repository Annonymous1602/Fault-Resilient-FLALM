#!/usr/bin/env python3
import argparse,csv,random,re,subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser()
p.add_argument('--width',type=int,choices=[1024,2048],default=1024)
p.add_argument('--mode',choices=['GMM','SMM'],default='GMM')
p.add_argument('--trials',type=int,default=100)
p.add_argument('--seed',type=int,default=2027)
p.add_argument('--max-occurrence',type=int,default=10,help='Choose among the first N valid Karatsuba operations')
a=p.parse_args()
if a.trials<1 or a.max_occurrence<1:p.error('trials and max-occurrence must be >=1')
subprocess.run([sys.executable,str(root/'scripts'/'make_campaign_tb.py')],check=True)
(root/'build').mkdir(exist_ok=True)
exe=root/'build'/f'campaign_{a.width}.vvp'
cmd=['iverilog','-g2012','-s',f'flalm_campaign_tb_{a.width}','-o',str(exe)]
cmd += sorted(map(str,(root/'secure_rtl').glob('*.v')))
cmd += [str(root/'security'/'karatsuba_residue_monitor.v'),str(root/'fault_injection'/f'flalm_campaign_tb_{a.width}.v')]
subprocess.run(cmd,check=True)
randomizer=random.Random(a.seed)
out=root/'fault_injection'/'results'/f'full_{a.width}_{a.mode}_r1_seed{a.seed}.csv'
out.parent.mkdir(exist_ok=True,parents=True)
keys=['trial','width','mode','bit','occurrence','injected','detected','corrupt','start','inject','alarm','done','absolute_cycles','expected']
rows=[]
for trial in range(a.trials):
    bit=randomizer.randrange(128)
    occurrence=randomizer.randint(1,a.max_occurrence)
    run=subprocess.run(['vvp',str(exe),f'+target={a.mode}',f'+bit={bit}',f'+occurrence={occurrence}'],capture_output=True,text=True)
    matches=re.findall(r'^CAMPAIGN_RESULT (.+)$',run.stdout,re.M)
    if run.returncode!=0 or len(matches)!=1:
        print('FAILED TRIAL',trial,'return code',run.returncode,'\n',run.stdout,'\n',run.stderr,file=sys.stderr)
        sys.exit(1)
    record={'trial':trial}
    record.update(dict(t.split('=',1) for t in matches[0].split()))
    record={k:(int(v) if k not in ('mode',) else v) for k,v in record.items()}
    rows.append(record)
    if (trial+1)%max(1,a.trials//10)==0:print('completed',trial+1,'/',a.trials,flush=True)
with out.open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=keys)
    w.writeheader(); w.writerows(rows)
detected=sum(r['detected'] for r in rows)
corrupt=sum(r['corrupt'] for r in rows)
sdc=sum(r['corrupt'] and not r['detected'] for r in rows)
print('RESULT trials=',len(rows),'detected=',detected,'corrupt=',corrupt,'silent_corrupt=',sdc)
print('Overall detection rate:',round(100*detected/len(rows),3),'%')
print('Output-corrupting fault detection rate:',round(100*(corrupt-sdc)/corrupt,3) if corrupt else 'N/A','%')
print('CSV:',out)
