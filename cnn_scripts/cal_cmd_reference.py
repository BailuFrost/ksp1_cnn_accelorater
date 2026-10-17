import json
from pathlib import Path
from model_packer import _finish_layer, instruction_fields, pack_base, pack_extension

ROOT = Path(__file__).resolve().parents[1]


def make_layer(kernel=3, channels=513, outputs=9, height=4, width=4, stride=1, padding=0, opcode='CONV'):
    hout = 1 if opcode in ('FC', 'GAP') else (height + 2*padding-kernel)//stride+1
    wout = 1 if opcode in ('FC', 'GAP') else (width + 2*padding-kernel)//stride+1
    item = _finish_layer(dict(name='d2', opcode_name=opcode, kernel=kernel,
        stride=stride, padding=padding, height=height, width=width,
        height_out=hout, width_out=wout, cin=channels, cout=outputs,
        input_fraction=0, weight_fraction=0, accumulator_fraction=0,
        output_fraction=0, result_shift=0, relu=0))
    item.update(layer_index=0, last=1, feature_addr=0x05000000,
        output_addr=0x0b000000, weight_addr=0x12000000,
        bias_addr=0x12000000+item['weight_elements']*2+64, aux_addr=0x05040000)
    return item


def schedule(item):
    op = item['opcode_name']
    h,w,cin,cout = (item[k] for k in ('height','width','cin','cout'))
    kh,s,p = (item[k] for k in ('kernel','stride','padding'))
    events = []
    if op in ('CONV','FC'):
        depth = item['input_elements'] if op=='FC' else cin
        parallel = 72 if op=='FC' or kh==1 else 8
        for group in range((cout+parallel-1)//parallel):
            for tile in range((depth+511)//512):
                active = min(512,depth-tile*512)
                for y in range(item['height_out']):
                    columns = 1 if op=='FC' else w+2*p
                    for x in range(columns):
                        real_x = x-p
                        top = 0 if op=='FC' else y*s-p
                        mask = sum((0<=top+r<h)<<r for r in range(1 if kh==1 or op=='FC' else kh))
                        role = top%3
                        for pair in range((active+1)//2):
                            address = (real_x if 0 <= real_x < w else 0)*((active+3)//4*2)+pair
                            events.append([group,tile,y,x,pair,address,pair,role,mask,
                                int(0<=real_x<w) if op!='FC' else 1,
                                1 if active%2 and pair==(active-1)//2 else 3])
    else:
        for y in range(item['height_out'] if op=='MAXPOOL' else h):
            for x in range(item['width_out'] if op=='MAXPOOL' else w):
                for quad in range((cout+3)//4):
                    for stage in range(4 if op=='MAXPOOL' else 1):
                        events.append([y*2+stage//2 if op=='MAXPOOL' else y,
                            x*2+stage%2 if op=='MAXPOOL' else x,quad,stage,
                            quad//128,quad%128,(1<<min(4,cout-quad*4))-1])
    return events


def main():
    cases = [make_layer(),make_layer(2,3,9,4,5,2,0),
        make_layer(1,513,73,2,2),make_layer(1,513,73,1,1,opcode='FC'),
        make_layer(3,3,8,3,4,1,1),make_layer(1,1,72,1,30),
        make_layer(2,513,513,4,2,2,0,'MAXPOOL'),
        make_layer(1,513,513,2,2,opcode='ADD'),
        make_layer(1,513,513,2,2,opcode='GAP')]
    configs=[]; pairs=[]; posts=[]; bundles=[]; beats=[]; meta=[]; info=[]
    for index,item in enumerate(cases):
        base,extension=instruction_fields(item)
        configs.append(f'{int.from_bytes(pack_extension(extension),"little"):064x}{int.from_bytes(pack_base(base),"little"):064x}')
        tokens=schedule(item)
        target=pairs if item['opcode_name'] in ('CONV','FC') else posts
        start=len(target)
        for e in tokens:
            if target is pairs:
                g,t,y,x,q,a,k,r,m,c,pm=e
                value=g|(t<<10)|(y<<18)|(x<<34)|(q<<48)|(a<<57)|(k<<70)|(r<<78)|(m<<80)|(c<<83)|(pm<<84)
                target.append(f'{value:024x}')
            else:
                y,x,g,st,b,q,m=e
                value=y|(x<<16)|(g<<28)|(st<<38)|(b<<40)|(q<<48)|(m<<55)
                target.append(f'{value:016x}')
        if target is pairs:
            expected_bundles,expected_beats = numerical_events(item)
            bundles.extend(expected_bundles)
            beats.extend(expected_beats)
        meta.append(f'{len(beats):08x}{len(bundles):08x}{len(posts):08x}{len(pairs):08x}')
        info.append(dict(index=index,opcode=item['opcode_name'],start=start,count=len(tokens),
            output_spatial=item['height_out']*item['width_out'],cout=item['cout']))
    for name,rows in [('configs',configs),('pairs',pairs),('posts',posts),('bundles',bundles),('beats',beats),('meta',meta)]:
        (ROOT/'tb'/f'd2_{name}.mem').write_text('\n'.join(rows)+'\n',encoding='ascii')
    (ROOT/'reports/d2/oracle.json').write_text(json.dumps(info,indent=2)+'\n',encoding='utf-8')
    assert len(schedule(cases[0])) == 4112
    assert len(schedule(cases[6]))==2*1*129*4
    assert schedule(cases[6])[-1][2:]==[128,3,1,0,1]
    assert len(beats) == 683 and len(bundles) == 86
    print(json.dumps(info))


def numerical_events(item):
    depth=item['input_elements'] if item['opcode_name']=='FC' else item['cin']
    parallel=72 if item['opcode_name']=='FC' or item['kernel']==1 else 8
    bundles=[]; beats=[]
    for group in range((item['cout']+parallel-1)//parallel):
        lanes=min(parallel,item['cout']-group*parallel)
        for tile in range((depth+511)//512):
            active=min(512,depth-tile*512)
            for y in range(item['height_out']):
                for x in range(item['width_out']):
                    feature_sum=0
                    for ky in range(item['kernel']):
                        for kx in range(item['kernel']):
                            iy=y*item['stride']+ky-item['padding']
                            ix=x*item['stride']+kx-item['padding']
                            if 0<=iy<item['height'] and 0<=ix<item['width']:
                                feature_sum += (iy*item['width']+ix)%7-3
                    values=[feature_sum*active*(1+(group*parallel+lane)%3) for lane in range(lanes)]
                    raw=sum((value&((1<<48)-1))<<(48*lane) for lane,value in enumerate(values))
                    spatial=y*item['width_out']+x
                    mask=(1<<lanes)-1
                    # 5184数据、108mask、32空间、10group、8tile、首末标志。
                    word=raw|(mask<<5184)|(spatial<<5292)|(group<<5324)|(tile<<5334)|((tile==0)<<5342)|((tile==(depth-1)//512)<<5343)
                    bundles.append(f'{word:1336x}')
                    if tile==(depth-1)//512:
                        for quad in range((lanes+3)//4):
                            valid=min(4,lanes-quad*4)
                            data=0
                            for lane in range(valid):
                                output=group*parallel+quad*4+lane
                                value=feature_sum*depth*(1+output%3)+output%5-2
                                value=max(-32768,min(32767,value))
                                data|=(value&65535)<<(lane*16)
                            beats.append(f'{int(parallel==72):01x}{(1<<valid)-1:01x}{data:016x}')
    return bundles,beats


if __name__=='__main__':
    main()
