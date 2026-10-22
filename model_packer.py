from __future__ import annotations

import hashlib
import math
import struct
from pathlib import Path
from typing import Any, BinaryIO

import torch
from torch import nn

from int16_golden import round_nearest_away


ALIGNMENT = 64
TILE_CHANNELS = 512
# Physical partial-sum storage stays 5292 x 192, stride 27; only 18 quads are active.
PSUM_STRIDE = 27
PSUM_WORDS = 5292
HARDWARE_PROFILE = dict(cu=8, spatial_parallel=8, bypass_parallel=72,
                        tile_channels=512, weight_block_bytes=73728, numerical_profile="INT16")
PACKAGE_VERSION = 2  # Fixed 8CU physical layout; base/extension instructions remain V1.
ROW_ELEMS_MAX = 16384
WEIGHT_BLOCK_ELEMENTS = 8 * 9 * TILE_CHANNELS
MAX_PSUM_ENTRIES = 196 * 72

DDR = {
    "instructions": (0x04000000, 0x00200000),
    "result": (0x04200000, 0x00200000),
    "feature": (0x05000000, 0x0C000000),
    "weights": (0x12000000, 0x14000000),
}
FEATURE_A = DDR["feature"][0]
FEATURE_B = FEATURE_A + DDR["feature"][1] // 2
FEATURE_BUFFER_BYTES = DDR["feature"][1] // 2

OPCODE = {"CONV": 0, "FC": 1, "MAXPOOL": 2, "ADD": 3, "GAP": 4}
MODE = {"3x3": 0, "2x2": 1, "1x1": 2, "matrix": 3}

BASE_FIELDS = (
    ("F_ADDR", 32),
    ("O_ADDR", 32),
    ("F_TRANS_NUM", 24),
    ("F_WRITE_SWITCH", 24),
    ("F_CAL_SWITCH", 24),
    ("F_WIDTH", 12),
    ("W_TRANS_NUM", 24),
    ("K_DEPTH", 12),
    ("K_NUM", 12),
    ("K_SIZE", 4),
    ("K_STRIDE_PADDLE", 4),
    ("O_TRANS_NUM", 24),
    ("LAYER_INDEX", 8),
    ("FILL", 12),
    ("RESERVED", 8),
)

HEADER = struct.Struct("<8s14I")
DIRECTORY_ENTRY = struct.Struct("<8s14I")
EXTENSION = struct.Struct("<8I")


def align_up(value: int, alignment: int = ALIGNMENT) -> int:
    return (value + alignment - 1) // alignment * alignment


def encode_12(value: int) -> int:
    """12 位论文深度/核数字段以 0 表示 4096。"""
    if value == 4096:
        return 0
    if not 0 < value < 4096:
        raise ValueError(f"12-bit dimension is out of range: {value}")
    return value


def decode_12(value: int) -> int:
    return 4096 if value == 0 else value


def pack_base(fields: dict[str, int]) -> bytes:
    value = 0
    offset = 0
    for name, width in BASE_FIELDS:
        field = fields[name]
        if not 0 <= field < (1 << width):
            raise ValueError(f"{name}={field} does not fit {width} bits")
        value |= field << offset
        offset += width
    assert offset == 256
    return value.to_bytes(32, "little")


def unpack_base(record: bytes) -> dict[str, int]:
    if len(record) != 32:
        raise ValueError("base instruction must be 32 bytes")
    value = int.from_bytes(record, "little")
    result = {}
    offset = 0
    for name, width in BASE_FIELDS:
        result[name] = (value >> offset) & ((1 << width) - 1)
        offset += width
    return result


def pack_extension(fields: dict[str, int]) -> bytes:
    word5 = (
        fields["result_shift"]
        | (fields["relu"] << 6)
        | (fields["last"] << 7)
        | (fields["opcode"] << 8)
        | (fields["src0_rshift"] << 12)
        | (fields["src1_rshift"] << 18)
        | (fields["w_trans_num_hi"] << 24)
    )
    words = (
        fields["weight_addr"],
        fields["bias_addr"],
        fields["aux_addr"],
        fields["height"] | (fields["height_out"] << 16),
        fields["cin_padded"] | (fields["cout_padded"] << 16),
        word5,
        fields["input_elements"],
        fields["expected_max_cycles"],
    )
    return EXTENSION.pack(*words)


def unpack_extension(record: bytes) -> dict[str, int]:
    if len(record) != 32:
        raise ValueError("extension instruction must be 32 bytes")
    words = EXTENSION.unpack(record)
    word5 = words[5]
    return {
        "weight_addr": words[0],
        "bias_addr": words[1],
        "aux_addr": words[2],
        "height": words[3] & 0xFFFF,
        "height_out": words[3] >> 16,
        "cin_padded": words[4] & 0xFFFF,
        "cout_padded": words[4] >> 16,
        "result_shift": word5 & 0x3F,
        "relu": (word5 >> 6) & 1,
        "last": (word5 >> 7) & 1,
        "opcode": (word5 >> 8) & 0xF,
        "src0_rshift": (word5 >> 12) & 0x3F,
        "src1_rshift": (word5 >> 18) & 0x3F,
        "w_trans_num_hi": word5 >> 24,
        "input_elements": words[6],
        "expected_max_cycles": words[7],
    }


def _finish_layer(layer: dict[str, Any]) -> dict[str, Any]:
    layer = dict(layer)
    layer["cin_padded"] = align_up(layer["cin"], 4)
    layer["cout_padded"] = align_up(layer["cout"], 4)
    layer["input_elements"] = layer["height"] * layer["width"] * layer["cin"]
    layer["input_bytes"] = layer["height"] * layer["width"] * layer["cin_padded"] * 2
    layer["output_bytes"] = layer["height_out"] * layer["width_out"] * layer["cout_padded"] * 2

    if layer["opcode_name"] == "CONV":
        parallel = 8 if layer["kernel"] in (2, 3) else 72
        weight_inputs = layer["cin"]
    elif layer["opcode_name"] == "FC":
        parallel = 72
        weight_inputs = layer["input_elements"]
        layer["cin_padded"] = align_up(weight_inputs, 4)
        layer["input_bytes"] = layer["cin_padded"] * 2
    else:
        parallel = 4
        weight_inputs = 0

    layer["parallel_outputs"] = parallel
    layer["input_tile_count"] = math.ceil(weight_inputs / TILE_CHANNELS) if weight_inputs else 0
    layer["output_group_count"] = math.ceil(layer["cout"] / parallel) if weight_inputs else 0
    layer["weight_elements"] = (
        layer["input_tile_count"] * layer["output_group_count"] * WEIGHT_BLOCK_ELEMENTS
    )
    layer["bias_elements"] = layer["output_group_count"] * parallel
    return layer




def assign_feature_addresses(layers: list[dict[str, Any]]) -> None:
    current = FEATURE_A
    for layer in layers:
        layer["feature_addr"] = current
        if layer["last"]:
            layer["output_addr"] = DDR["result"][0]
        else:
            layer["output_addr"] = FEATURE_B if current == FEATURE_A else FEATURE_A
        current = layer["output_addr"]


def assign_weight_layout(layers: list[dict[str, Any]]) -> dict[str, int]:
    weighted = [layer for layer in layers if layer["weight_elements"]]
    directory_offset = HEADER.size
    payload_offset = align_up(directory_offset + len(weighted) * DIRECTORY_ENTRY.size)
    cursor = payload_offset
    for layer in weighted:
        cursor = align_up(cursor)
        layer["weight_offset"] = cursor
        layer["weight_bytes"] = layer["weight_elements"] * 2
        cursor += layer["weight_bytes"]
        cursor = align_up(cursor)
        layer["bias_offset"] = cursor
        layer["bias_bytes"] = layer["bias_elements"] * 8
        cursor += layer["bias_bytes"]
        layer["weight_addr"] = DDR["weights"][0] + layer["weight_offset"]
        layer["bias_addr"] = DDR["weights"][0] + layer["bias_offset"]
    return {
        "directory_offset": directory_offset,
        "directory_entries": len(weighted),
        "payload_offset": payload_offset,
        "file_bytes": align_up(cursor),
    }


def instruction_fields(layer: dict[str, Any]) -> tuple[dict[str, int], dict[str, int]]:
    # 最大tile能装下一行，则所有尾tile均满足C0容量；FC只缓存单个展平向量。
    matrix = layer["opcode_name"] == "FC"
    logical_channels = layer["input_elements"] if matrix else layer["cin"]
    row_elements = (1 if matrix else layer["width"]) * align_up(min(logical_channels, TILE_CHANNELS), 4)
    if row_elements > ROW_ELEMS_MAX:
        raise ValueError(f"{layer['name']}: C0 row needs {row_elements} INT16 elements, capacity is {ROW_ELEMS_MAX}")

    opcode = OPCODE[layer["opcode_name"]]
    if layer["opcode_name"] == "FC":
        mode = MODE["matrix"]
        input_elements = layer["input_elements"]
        k_depth = 0
    elif layer["opcode_name"] == "CONV":
        mode = MODE[f"{layer['kernel']}x{layer['kernel']}"]
        input_elements = 0
        k_depth = encode_12(layer["cin"])
    else:
        mode = MODE["2x2"]
        input_elements = 0
        k_depth = encode_12(layer["cin"])

    weight_elements = layer["weight_elements"]
    if layer["opcode_name"] in ("CONV", "FC"):
        expected = layer["output_group_count"] * layer["input_tile_count"] * WEIGHT_BLOCK_ELEMENTS
        if weight_elements != expected:
            raise AssertionError(f"{layer['name']}: packed weight count is inconsistent")
    base = {
        "F_ADDR": layer["feature_addr"],
        "O_ADDR": layer["output_addr"],
        "F_TRANS_NUM": layer["input_bytes"] // 2,
        "F_WRITE_SWITCH": layer["height"] * layer["width"],
        "F_CAL_SWITCH": layer["width"] * layer["cin_padded"],
        "F_WIDTH": layer["width"],
        "W_TRANS_NUM": weight_elements & 0xFFFFFF,
        "K_DEPTH": k_depth,
        "K_NUM": encode_12(layer["cout"]),
        "K_SIZE": mode,
        "K_STRIDE_PADDLE": layer["stride"] | (layer["padding"] << 2),
        "O_TRANS_NUM": layer["output_bytes"] // 2,
        "LAYER_INDEX": layer["layer_index"],
        "FILL": 0,
        "RESERVED": 0,
    }
    extension = {
        "weight_addr": layer.get("weight_addr", 0),
        "bias_addr": layer.get("bias_addr", 0),
        "aux_addr": 0,
        "height": layer["height"],
        "height_out": layer["height_out"],
        "cin_padded": layer["cin_padded"],
        "cout_padded": layer["cout_padded"],
        "result_shift": layer["result_shift"],
        "relu": layer["relu"],
        "last": layer["last"],
        "opcode": opcode,
        "src0_rshift": 0,
        "src1_rshift": 0,
        "w_trans_num_hi": weight_elements >> 24,
        "input_elements": input_elements,
        "expected_max_cycles": 0,
    }
    return base, extension


def _quantize(value: torch.Tensor, fraction_bits: int) -> torch.Tensor:
    scaled = round_nearest_away(value.to(torch.float64) * (2.0**fraction_bits))
    return scaled.clamp(-32768, 32767).to(torch.int16)


def _module(model: nn.Module, source: str) -> nn.Module:
    return model.get_submodule(source)


def _write_at(stream: BinaryIO, offset: int, data: bytes) -> None:
    stream.seek(offset)
    stream.write(data)


def write_weight_file(path: Path, model: nn.Module, layers: list[dict[str, Any]], layout: dict[str, int]) -> None:
    weighted = [layer for layer in layers if layer["weight_elements"]]
    header = HEADER.pack(
        b"CNNWGT\0\0",
        PACKAGE_VERSION,
        HEADER.size,
        1,
        len(weighted),
        layout["directory_offset"],
        DIRECTORY_ENTRY.size,
        layout["payload_offset"],
        layout["file_bytes"],
        16,
        1,
        1,
        0,
        0,
        0,
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as stream:
        stream.write(header)
        for layer in weighted:
            name_hash = (layer["name_id"] if "name_id" in layer else
                         hashlib.sha256(layer["name"].encode("utf-8")).digest()[:8])
            stream.write(
                DIRECTORY_ENTRY.pack(
                    name_hash,
                    layer["layer_index"],
                    OPCODE[layer["opcode_name"]],
                    layer["kernel"],
                    layer["weight_offset"],
                    layer["weight_bytes"],
                    layer["bias_offset"],
                    layer["bias_bytes"],
                    layer["input_elements"],
                    layer["cout"],
                    layer["input_fraction"],
                    layer["weight_fraction"],
                    layer["accumulator_fraction"],
                    layer["output_fraction"],
                    layer["result_shift"],
                )
            )

        for layer in weighted:
            module = _module(model, layer["source"])
            weight = module.weight.detach()
            stream.seek(layer["weight_offset"])
            for group in range(layer["output_group_count"]):
                output_base = group * layer["parallel_outputs"]
                valid_outputs = min(layer["parallel_outputs"], layer["cout"] - output_base)
                for tile in range(layer["input_tile_count"]):
                    input_base = tile * TILE_CHANNELS
                    weight_inputs = layer["input_elements"] if layer["opcode_name"] == "FC" else layer["cin"]
                    valid_inputs = min(TILE_CHANNELS, weight_inputs - input_base)
                    block = torch.zeros((8, 9, TILE_CHANNELS), dtype=torch.int16)
                    if layer["opcode_name"] == "CONV":
                        chunk = weight[
                            output_base : output_base + valid_outputs,
                            input_base : input_base + valid_inputs,
                            :,
                            :,
                        ]
                        quantized = _quantize(chunk, layer["weight_fraction"])
                        if layer["kernel"] == 3:
                            block[:valid_outputs, :, :valid_inputs] = quantized.permute(0, 2, 3, 1).reshape(
                                valid_outputs, 9, valid_inputs
                            )
                        elif layer["kernel"] == 2:
                            for row in range(2):
                                block[:valid_outputs, row * 3:row * 3 + 2, :valid_inputs] = (
                                    quantized[:, :, row, :].permute(0, 2, 1)
                                )
                        else:
                            block.reshape(72, TILE_CHANNELS)[:valid_outputs, :valid_inputs] = quantized[:, :, 0, 0]
                    else:
                        if layer["height"] * layer["width"] > 1:
                            hwc = torch.arange(input_base, input_base + valid_inputs)
                            channel = hwc % layer["cin"]
                            spatial = torch.div(hwc, layer["cin"], rounding_mode="floor")
                            chw_indices = channel * layer["height"] * layer["width"] + spatial
                            chunk = weight[output_base : output_base + valid_outputs][:, chw_indices]
                        else:
                            chunk = weight[
                                output_base : output_base + valid_outputs,
                                input_base : input_base + valid_inputs,
                            ]
                        block.reshape(72, TILE_CHANNELS)[:valid_outputs, :valid_inputs] = _quantize(
                            chunk, layer["weight_fraction"]
                        )
                    stream.write(block.numpy().astype("<i2", copy=False).tobytes())

            bias = module.bias.detach().to(torch.float64)
            bias_integer = round_nearest_away(bias * (2.0 ** layer["accumulator_fraction"])).to(torch.int64)
            if int(bias_integer.abs().max()) >= (1 << 47):
                raise OverflowError(f"{layer['name']}: bias exceeds signed 48-bit range")
            padded_bias = torch.zeros(layer["bias_elements"], dtype=torch.int64)
            padded_bias[: layer["cout"]] = bias_integer
            _write_at(
                stream,
                layer["bias_offset"],
                padded_bias.numpy().astype("<i8", copy=False).tobytes(),
            )
        stream.truncate(layout["file_bytes"])


def write_command_file(path: Path, layers: list[dict[str, Any]]) -> dict[str, int]:
    base_offset = HEADER.size
    extension_offset = align_up(base_offset + len(layers) * 32)
    file_bytes = align_up(extension_offset + len(layers) * 32)
    header = HEADER.pack(
        b"CNNCMD\0\0",
        PACKAGE_VERSION,
        HEADER.size,
        16,
        len(layers),
        base_offset,
        32,
        extension_offset,
        32,
        DDR["instructions"][0] + DDR["instructions"][1] - 64,
        1,
        1,
        file_bytes,
        1,
        0,
    )
    content = bytearray(file_bytes)
    content[: HEADER.size] = header
    for index, layer in enumerate(layers):
        base, extension = instruction_fields(layer)
        content[base_offset + index * 32 : base_offset + (index + 1) * 32] = pack_base(base)
        content[extension_offset + index * 32 : extension_offset + (index + 1) * 32] = pack_extension(extension)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)
    return {"base_offset": base_offset, "extension_offset": extension_offset, "file_bytes": file_bytes}


def _within(address: int, size: int, region: tuple[int, int]) -> bool:
    return region[0] <= address and address + size <= region[0] + region[1]


def validate_layers(layers: list[dict[str, Any]], weight_layout: dict[str, int]) -> None:
    if not 0 < len(layers) <= 256:
        raise ValueError("layer count must fit the 256-entry instruction BRAM")
    if weight_layout["file_bytes"] > DDR["weights"][1]:
        raise ValueError("weight file exceeds the DDR weight partition")

    regions = sorted((base, base + size, name) for name, (base, size) in DDR.items())
    for left, right in zip(regions, regions[1:]):
        if left[1] > right[0]:
            raise ValueError(f"DDR partitions overlap: {left[2]} and {right[2]}")

    intervals = []
    for layer in layers:
        expected_height = (layer["height"] + 2 * layer["padding"] - layer["kernel"]) // layer["stride"] + 1
        expected_width = (layer["width"] + 2 * layer["padding"] - layer["kernel"]) // layer["stride"] + 1
        if layer["opcode_name"] != "FC" and (
            expected_height != layer["height_out"] or expected_width != layer["width_out"]
        ):
            raise ValueError(f"{layer['name']}: invalid output shape")
        if layer["feature_addr"] % 8 or layer["output_addr"] % 8:
            raise ValueError(f"{layer['name']}: feature address is not 8-byte aligned")
        if not _within(layer["feature_addr"], layer["input_bytes"], DDR["feature"]):
            raise ValueError(f"{layer['name']}: input exceeds feature DDR")
        output_region = DDR["result"] if layer["last"] else DDR["feature"]
        if not _within(layer["output_addr"], layer["output_bytes"], output_region):
            raise ValueError(f"{layer['name']}: output exceeds its DDR partition")
        if not (
            layer["feature_addr"] + layer["input_bytes"] <= layer["output_addr"]
            or layer["output_addr"] + layer["output_bytes"] <= layer["feature_addr"]
        ):
            raise ValueError(f"{layer['name']}: live input and output overlap")
        if layer["input_tile_count"] > 1 and (
            layer["height_out"] * layer["width_out"] > 196
        ):
            raise ValueError(f"{layer['name']}: tile psum buffer would overflow")

        base, extension = instruction_fields(layer)
        if unpack_base(pack_base(base)) != base or unpack_extension(pack_extension(extension)) != extension:
            raise AssertionError(f"{layer['name']}: instruction round-trip failed")
        reconstructed_weights = base["W_TRANS_NUM"] | (extension["w_trans_num_hi"] << 24)
        if reconstructed_weights != layer["weight_elements"]:
            raise AssertionError(f"{layer['name']}: weight count cannot be reconstructed")

        if layer["weight_elements"]:
            for key in ("weight", "bias"):
                offset = layer[f"{key}_offset"]
                size = layer[f"{key}_bytes"]
                if offset % ALIGNMENT or offset + size > weight_layout["file_bytes"]:
                    raise ValueError(f"{layer['name']}: invalid {key} range")
                intervals.append((offset, offset + size, f"{layer['name']}:{key}"))

    intervals.sort()
    for left, right in zip(intervals, intervals[1:]):
        if left[1] > right[0]:
            raise ValueError(f"weight payloads overlap: {left[2]} and {right[2]}")


def _read_integer(path: Path, offset: int, width: int, signed: bool = True) -> int:
    with path.open("rb") as stream:
        stream.seek(offset)
        data = stream.read(width)
    if len(data) != width:
        raise AssertionError(f"short read at file offset {offset}")
    return int.from_bytes(data, "little", signed=signed)


def validate_weight_samples(weight_path: Path, model: nn.Module, layers: list[dict[str, Any]]) -> int:
    checked = 0
    block_bytes = WEIGHT_BLOCK_ELEMENTS * 2
    for layer in (item for item in layers if item["weight_elements"]):
        module = _module(model, layer["source"])
        weight_inputs = layer["input_elements"] if layer["opcode_name"] == "FC" else layer["cin"]
        samples = [(0, 0, 0), (layer["cout"] - 1, weight_inputs - 1, layer["kernel"] ** 2 - 1)]
        if layer["opcode_name"] == "FC" and layer["height"] * layer["width"] > 1:
            samples.extend(((0, 1, 0), (0, layer["cin"], 0)))
        for output, input_index, kernel_index in samples:
            group, lane = divmod(output, layer["parallel_outputs"])
            tile, element = divmod(input_index, TILE_CHANNELS)
            if layer["opcode_name"] == "CONV":
                row, column = divmod(kernel_index, layer["kernel"])
                cu, bank = divmod(lane, 9) if layer["kernel"] == 1 else (lane, row * 3 + column)
                source_value = module.weight[output, input_index, row, column]
            else:
                cu, bank = divmod(lane, 9)
                if layer["height"] * layer["width"] > 1:
                    spatial, channel = divmod(input_index, layer["cin"])
                    source_index = channel * layer["height"] * layer["width"] + spatial
                else:
                    source_index = input_index
                source_value = module.weight[output, source_index]
            offset = (
                layer["weight_offset"]
                + (group * layer["input_tile_count"] + tile) * block_bytes
                + ((cu * 9 + bank) * TILE_CHANNELS + element) * 2
            )
            expected = int(_quantize(source_value.reshape(1), layer["weight_fraction"])[0])
            if _read_integer(weight_path, offset, 2) != expected:
                raise AssertionError(f"{layer['name']}: reordered weight sample differs")
            checked += 1

        if layer["cout"] % layer["parallel_outputs"]:
            padded_lane = layer["cout"] % layer["parallel_outputs"]
            spatial_conv = layer["opcode_name"] == "CONV" and layer["kernel"] in (2, 3)
            cu, bank = (padded_lane, 0) if spatial_conv else divmod(padded_lane, 9)
            offset = (
                layer["weight_offset"]
                + (layer["output_group_count"] - 1) * layer["input_tile_count"] * block_bytes
                + (cu * 9 + bank) * TILE_CHANNELS * 2
            )
            if _read_integer(weight_path, offset, 2) != 0:
                raise AssertionError(f"{layer['name']}: output tail is not zero padded")
            checked += 1
        if weight_inputs % TILE_CHANNELS:
            padded_element = weight_inputs % TILE_CHANNELS
            offset = (
                layer["weight_offset"]
                + (layer["input_tile_count"] - 1) * block_bytes
                + padded_element * 2
            )
            if _read_integer(weight_path, offset, 2) != 0:
                raise AssertionError(f"{layer['name']}: input tail is not zero padded")
            checked += 1

        bias_integer = round_nearest_away(
            module.bias.detach().to(torch.float64) * (2.0 ** layer["accumulator_fraction"])
        ).to(torch.int64)
        for index in (0, layer["cout"] - 1):
            if _read_integer(weight_path, layer["bias_offset"] + index * 8, 8) != int(bias_integer[index]):
                raise AssertionError(f"{layer['name']}: quantized bias sample differs")
            checked += 1
        if layer["bias_elements"] > layer["cout"]:
            if _read_integer(weight_path, layer["bias_offset"] + layer["cout"] * 8, 8) != 0:
                raise AssertionError(f"{layer['name']}: bias tail is not zero padded")
            checked += 1
    return checked


def validate_files(
    command_path: Path,
    weight_path: Path,
    model: nn.Module,
    layers: list[dict[str, Any]],
    layouts: dict[str, Any],
) -> int:
    command = command_path.read_bytes()
    header = HEADER.unpack(command[: HEADER.size])
    expected_header = (b"CNNCMD\0\0", PACKAGE_VERSION, HEADER.size, 16, len(layers),
                       layouts["command"]["base_offset"], 32, layouts["command"]["extension_offset"], 32,
                       DDR["instructions"][0] + DDR["instructions"][1] - 64,
                       1, 1, layouts["command"]["file_bytes"], 1, 0)
    if header != expected_header or len(command) != layouts["command"]["file_bytes"]:
        raise AssertionError("command header validation failed")
    for index, layer in enumerate(layers):
        base_expected, extension_expected = instruction_fields(layer)
        base_offset = layouts["command"]["base_offset"] + index * 32
        extension_offset = layouts["command"]["extension_offset"] + index * 32
        if unpack_base(command[base_offset : base_offset + 32]) != base_expected:
            raise AssertionError(f"{layer['name']}: stored base instruction differs")
        if unpack_extension(command[extension_offset : extension_offset + 32]) != extension_expected:
            raise AssertionError(f"{layer['name']}: stored extension differs")

    with weight_path.open("rb") as stream:
        weight_header = HEADER.unpack(stream.read(HEADER.size))
        expected_weight_header = (b"CNNWGT\0\0", PACKAGE_VERSION, HEADER.size, 1,
                                  layouts["weights"]["directory_entries"],
                                  layouts["weights"]["directory_offset"], DIRECTORY_ENTRY.size,
                                  layouts["weights"]["payload_offset"], layouts["weights"]["file_bytes"],
                                  16, 1, 1, 0, 0, 0)
        if weight_header != expected_weight_header:
            raise AssertionError("weight header validation failed")
        stream.seek(weight_header[5])
        directory = [DIRECTORY_ENTRY.unpack(stream.read(weight_header[6])) for _ in range(weight_header[4])]
    if (
        weight_header[0] != b"CNNWGT\0\0"
        or weight_header[1] != PACKAGE_VERSION
        or weight_header[4] != layouts["weights"]["directory_entries"]
        or weight_path.stat().st_size != layouts["weights"]["file_bytes"]
    ):
        raise AssertionError("weight header validation failed")
    weighted = [layer for layer in layers if layer["weight_elements"]]
    for entry, layer in zip(directory, weighted):
        expected = (
            (layer["name_id"] if "name_id" in layer else
             hashlib.sha256(layer["name"].encode("utf-8")).digest()[:8]),
            layer["layer_index"],
            OPCODE[layer["opcode_name"]],
            layer["kernel"],
            layer["weight_offset"],
            layer["weight_bytes"],
            layer["bias_offset"],
            layer["bias_bytes"],
            layer["input_elements"],
            layer["cout"],
            layer["input_fraction"],
            layer["weight_fraction"],
            layer["accumulator_fraction"],
            layer["output_fraction"],
            layer["result_shift"],
        )
        if entry != expected:
            raise AssertionError(f"{layer['name']}: weight directory entry differs")
    return validate_weight_samples(weight_path, model, layers)


def synthetic_boundary_layers() -> list[dict[str, Any]]:
    definitions = [
        ("conv3x3_tail_tile_group", "CONV", 3, 14, 14, 513, 13),
        ("conv1x1_tail_108_group", "CONV", 1, 14, 14, 512, 109),
        ("fc6_32bit_weight_count", "FC", 1, 7, 7, 512, 4096),
    ]
    result = []
    for index, (name, opcode_name, kernel, height, width, cin, cout) in enumerate(definitions):
        layer = _finish_layer(
            {
                "name": name,
                "source": name,
                "opcode_name": opcode_name,
                "kernel": kernel,
                "stride": 1,
                "padding": 1 if kernel == 3 else 0,
                "height": height,
                "width": width,
                "height_out": height if opcode_name == "CONV" else 1,
                "width_out": width if opcode_name == "CONV" else 1,
                "cin": cin,
                "cout": cout,
                "input_fraction": 10,
                "weight_fraction": 15,
                "accumulator_fraction": 25,
                "output_fraction": 10,
                "result_shift": 15,
                "relu": 1,
            }
        )
        layer.update(
            {
                "layer_index": index,
                "last": int(index == len(definitions) - 1),
                "feature_addr": FEATURE_A,
                "output_addr": FEATURE_B,
                "weight_addr": DDR["weights"][0],
                "bias_addr": DDR["weights"][0] + align_up(layer["weight_elements"] * 2),
            }
        )
        base, extension = instruction_fields(layer)
        if unpack_base(pack_base(base)) != base or unpack_extension(pack_extension(extension)) != extension:
            raise AssertionError(f"{name}: synthetic instruction round-trip failed")
        if name == "fc6_32bit_weight_count" and layer["weight_elements"] <= 0xFFFFFF:
            raise AssertionError("FC6 synthetic layer did not exercise W_TRANS_NUM_HI")
        if not _within(layer["feature_addr"], layer["input_bytes"], DDR["feature"]):
            raise AssertionError(f"{name}: synthetic input address is out of bounds")
        if not _within(layer["output_addr"], layer["output_bytes"], DDR["feature"]):
            raise AssertionError(f"{name}: synthetic output address is out of bounds")
        if layer["feature_addr"] + layer["input_bytes"] > layer["output_addr"]:
            raise AssertionError(f"{name}: synthetic live feature ranges overlap")
        if layer["bias_addr"] + layer["bias_elements"] * 8 > DDR["weights"][0] + DDR["weights"][1]:
            raise AssertionError(f"{name}: synthetic weight range is out of bounds")
        if layer["input_tile_count"] > 1 and (
            layer["height_out"] * layer["width_out"] > 196
        ):
            raise AssertionError(f"{name}: synthetic tile psum range is out of bounds")
        result.append(
            {
                "name": name,
                "input_tile_count": layer["input_tile_count"],
                "output_group_count": layer["output_group_count"],
                "weight_elements": layer["weight_elements"],
                "w_trans_num_low": base["W_TRANS_NUM"],
                "w_trans_num_hi": extension["w_trans_num_hi"],
                "addresses_valid": True,
                "round_trip": True,
            }
        )
    return result


def run_self_check() -> None:
    assert align_up(65) == 128
    assert encode_12(4096) == 0 and decode_12(0) == 4096
    fields = {name: (index + 1) & ((1 << width) - 1) for index, (name, width) in enumerate(BASE_FIELDS)}
    assert unpack_base(pack_base(fields)) == fields
    assert len(synthetic_boundary_layers()) == 3
    capacity_cases = [
        ("CONV", 32, 512, True),
        ("CONV", 33, 512, False),
        ("CONV", 32, 513, True),
        ("CONV", 2048, 5, True),
        ("CONV", 2049, 5, False),
        ("FC", 64, 8, True),
        ("MAXPOOL", 33, 512, False),
        ("ADD", 33, 512, False),
        ("GAP", 33, 512, False),
    ]
    for opcode_name, width, channels, accepted in capacity_cases:
        layer = _finish_layer(dict(
            name="capacity_boundary", opcode_name=opcode_name, kernel=1, stride=1, padding=0,
            height=1, width=width, height_out=1, width_out=1, cin=channels, cout=4,
            layer_index=0, last=1, feature_addr=FEATURE_A, output_addr=FEATURE_B,
            result_shift=0, relu=0,
        ))
        try:
            base, extension = instruction_fields(layer)
        except ValueError as error:
            assert not accepted and "C0 row needs" in str(error), (opcode_name, width, channels, error)
        else:
            assert accepted, (opcode_name, width, channels)
            assert unpack_base(pack_base(base)) == base
            assert unpack_extension(pack_extension(extension)) == extension

    weighted = _finish_layer(dict(layer, opcode_name="CONV", width=1, cin=512))
    for count in (0, weighted["weight_elements"] - 4, weighted["weight_elements"] + 4):
        try:
            instruction_fields(dict(weighted, weight_elements=count))
        except AssertionError as error:
            assert "packed weight count is inconsistent" in str(error), error
        else:
            raise AssertionError("inconsistent software weight count accepted")


def _report_layer(layer: dict[str, Any]) -> dict[str, Any]:
    base, extension = instruction_fields(layer)
    return {
        "index": layer["layer_index"],
        "name": layer["name"],
        "opcode": layer["opcode_name"],
        "input_shape_hwc": [layer["height"], layer["width"], layer["cin"]],
        "output_shape_hwc": [layer["height_out"], layer["width_out"], layer["cout"]],
        "input_address": f"0x{layer['feature_addr']:08x}",
        "input_bytes": layer["input_bytes"],
        "output_address": f"0x{layer['output_addr']:08x}",
        "output_bytes": layer["output_bytes"],
        "weight_address": f"0x{layer.get('weight_addr', 0):08x}",
        "weight_bytes": layer.get("weight_bytes", 0),
        "bias_address": f"0x{layer.get('bias_addr', 0):08x}",
        "bias_bytes": layer.get("bias_bytes", 0),
        "input_tiles": layer["input_tile_count"],
        "output_groups": layer["output_group_count"],
        "base_instruction": base,
        "extension": extension,
    }
