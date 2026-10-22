import json
from pathlib import Path
import sys
import zipfile

import torch

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "cnn_scripts"))

from vgg16_model import VGG16
from make_layer import make_layer
from model_packer import (
    HARDWARE_PROFILE, PACKAGE_VERSION, 
    assign_feature_addresses, assign_weight_layout, validate_layers,
    write_command_file, write_weight_file,
)
from vgg_reference import prepare_parameters

DEFAULT_OUTPUT = ROOT / "cnn_scripts/weight/vgg16"
CHECKPOINT = ROOT / "cnn_scripts/weight/vgg16.pth"
REFERENCE = Path(__file__).resolve().parent / "reports/VGG"

def write_json(path, value):
    with Path(path).open("x", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2, allow_nan=False)
        stream.write("\n")

def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))

def require(condition, message):
    if not condition:
        raise ValueError(message)

def build_layers(config,quantization):
    layers = []
    count = len(config["layers"])
    require(0 < count == len(quantization["layers"]), "config.json和quantization.json的层数不一致")
    for index, (spec,quant) in enumerate(zip(config["layers"],quantization["layers"])):
        h,w,c = spec["input_hwc"]
        layer = make_layer(spec["kernel"], c, spec["output_hwc"][2], h, w,
                           spec["stride"], spec["padding"], spec["opcode"])
        layer.update(name=spec["name"], source=spec["name"], layer_index=index,
                     last=int(index == count -1), relu=int(quant["relu"]),
                     input_fraction=quant["input_fraction"],
                     weight_fraction=quant.get("weight_fraction", 0),
                     accumulator_fraction=quant.get("accumulator_fraction", quant["input_fraction"]),
                     output_fraction=quant["output_fraction"], result_shift=quant["result_shift"])
        layers.append(layer)
    assign_feature_addresses(layers)
    layout = assign_weight_layout(layers)
    validate_layers(layers, layout)
    return layers, layout


def check_hardware(config):
    hardware = dict(config["hardware"])
    bundle = ROOT / hardware["bundle"]
    require(set(hardware["required_capabilities"]) <= set(hardware["capabilities"]), "硬件能力不足")
    require(all(hardware[key] == value for key, value in HARDWARE_PROFILE.items()
                if key in hardware)
            and hardware["package_version"] == PACKAGE_VERSION, "硬件布局不匹配")
    names = ("e_j2_system_wrapper.bit", "e_j2.xsa", "ps7_init.tcl", "address_map.tcl")
    records = []
    for name in names:
        path = bundle / name
        require(path.is_file() and path.stat().st_size > 0, f"硬件文件缺失或为空：{name}")
        records.append({"path": path.relative_to(ROOT).as_posix(), "bytes": path.stat().st_size})
    with zipfile.ZipFile(bundle / "e_j2.xsa") as archive:
        for name, embedded in (("e_j2_system_wrapper.bit", "e_j2.bit"), ("ps7_init.tcl", "ps7_init.tcl")):
            members = [member for member in archive.namelist() if Path(member).name == embedded]
            require(len(members) == 1 and archive.read(members[0]) == (bundle / name).read_bytes(),
                    f"XSA 内外文件不一致：{name}")
    require("set csr_base " + hardware["csr_base"] in (bundle / "address_map.tcl").read_text(), "CSR 地址不匹配")
    require("CONFIG.PCW_CLK0_FREQ {100000000}" in (bundle / "e_j2_system_bd.tcl").read_text(), "FCLK 配置不匹配")
    return {**hardware, "verified_artifacts": records}

def load_checkpoint(path):
    state_dict = torch.load(path, map_location="cpu", weights_only=True)
    model = VGG16()
    model.load_state_dict(state_dict, strict=True)
    return model.eval()

def source_context():
    config = load_json(ROOT / "hardware/vgg16_config.json")
    hardware = check_hardware(config)
    quant = load_json(REFERENCE / "quantization.json")
    model = load_checkpoint(CHECKPOINT)
    cache, bounds = prepare_parameters(model, quant)
    require(bounds == quant["accumulator_bounds"], "signed48 累加范围不匹配")
    sources = [CHECKPOINT, ROOT / "hardware/vgg16_config.json", REFERENCE / "quantization.json"]
    return config, quant, model, cache, hardware, sources

def generate(directory):
    config, quant, model, _, _, _ = source_context()
    layers, weights = build_layers(config, quant)
    directory.mkdir(parents=True)
    write_command_file(directory / "vgg_cmd.bin", layers)
    write_weight_file(directory / "vgg_weights.bin", model, layers, weights)
    (directory / "quantization.json").write_bytes((REFERENCE / "quantization.json").read_bytes())

def main():
    generate(DEFAULT_OUTPUT)

if __name__ == "__main__":
    main()