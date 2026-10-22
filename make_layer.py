from model_packer import _finish_layer


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
