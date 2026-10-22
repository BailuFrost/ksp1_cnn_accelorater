import struct


def pool_hwc(values, height, width, channels):
    """输入不含补齐 lane；输出保持 HWC 和 signed INT16。"""
    if height < 2 or width < 2 or height % 2 or width % 2 or not 1 <= channels <= 4096:
        raise ValueError('MAXPOOL requires even H/W, 1..4096 channels')
    if len(values) != height * width * channels or any(not -32768 <= x <= 32767 for x in values):
        raise ValueError('input shape or INT16 range mismatch')
    return [max(values[((2*y+dy)*width+2*x+dx)*channels+c]
                for dy in range(2) for dx in range(2))
            for y in range(height//2) for x in range(width//2) for c in range(channels)]


def physical(values, channels):
    """每像素通道向四对齐，低 lane 在低位。"""
    padded = (channels + 3) // 4 * 4
    return b''.join(struct.pack('<' + 'h'*padded, *values[i:i+channels], *([0]*(padded-channels)))
                    for i in range(0, len(values), channels))


def read_addresses(base, height, width, channels):
    """坐标公式独立计算，不模拟 RTL 的递增地址实现。"""
    padded = (channels + 3) // 4 * 4
    return [base + ((2*y+dy)*width+2*x+dx)*padded*2 + quad*8
            for y in range(height//2) for x in range(width//2)
            for quad in range(padded//4) for dy in range(2) for dx in range(2)]


def self_check():
    assert pool_hwc([-32768, -1, -2, -3], 2, 2, 1) == [-1]
    assert pool_hwc([-32768]*4, 2, 2, 1) == [-32768]
    assert physical([-1], 1) == b'\xff\xff' + b'\0'*6
    for channels in [1, 3, 4, 5, 512, 513, 1025, 4096]:
        values = [((i*7919+17) % 65536)-32768 for i in range(4*6*channels)]
        result = pool_hwc(values, 4, 6, channels)
        addresses = read_addresses(0x05000000, 4, 6, channels)
        payload = physical(values, channels)
        quads = []
        for index in range(0, len(addresses), 4):
            corners = [struct.unpack_from('<4h', payload, a-0x05000000) for a in addresses[index:index+4]]
            quads.append(struct.pack('<4h', *(max(c[lane] for c in corners) for lane in range(4))))
        assert b''.join(quads) == physical(result, channels)
    for shape in [(3, 2, 1), (2, 3, 1), (2, 2, 0)]:
        try:
            pool_hwc([], *shape)
        except ValueError:
            continue
        raise AssertionError(shape)
    print('PASS pool reference: signed extremes, HWC, 8 channel boundaries, invalid geometry')


if __name__ == '__main__':
    self_check()
