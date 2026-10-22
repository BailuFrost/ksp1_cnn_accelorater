"""离线单元测试；合成记录不能作为板端验证证据。"""
import contextlib
import copy
import io
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from PIL import Image

import infer_vgg as deploy
from feature_input import prepare_batch


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix=".vgg_deploy_test_", dir=deploy.ROOT)
        self.root = Path(self.temporary.name).resolve()
        self.assertEqual(self.root.parent, deploy.ROOT.resolve())
        self.addCleanup(self.temporary.cleanup)

    def request(self):
        source = self.root / "source"
        source.mkdir()
        files = {}
        for name in deploy.TRANSFERS:
            path = source / name
            path.write_bytes(b"synthetic " + name.encode())
            files[name] = {**deploy.TRANSFERS[name], "source": str(path), "bytes": path.stat().st_size}
        hardware = source / "bitstream.bit"
        hardware.write_bytes(b"synthetic bitstream")
        return {"files": files, "hardware_files": {hardware.name: {"source": str(hardware), "bytes": hardware.stat().st_size}},
                "sample": {"model": "VGG16"}, "output_fraction": 7, "fclk_hz": 100000000}

    def completed(self, request):
        run = self.root / "run"
        deploy.prepare(run, request)
        for name in request["files"]:
            shutil.copyfile(run / "payload" / name, run / f"{name}.readback")
        cycles = (1 << 32) + 12345
        (run / "execution_kind.txt").write_text("HARDWARE")
        (run / "result.txt").write_text("PASS VGG16 execution")
        (run / "csr.txt").write_text(f"2 0 20 {cycles}")
        (run / "runtime.bin").write_bytes(struct.pack("<QII", cycles, 20, 1))
        logits = [-200] * 1000
        logits[999] = 32767
        (run / "output.bin").write_bytes(struct.pack("<1000h", *logits))
        return run, cycles

    def test_prepare_snapshot_no_overwrite(self):
        request = self.request()
        run = self.root / "run"
        deploy.prepare(run, request)
        self.assertEqual(json.loads((run / "request.json").read_text()), request)
        self.assertFalse((run / "payload/expected.bin").exists())
        self.assertFalse((run / "payload/artifact_hashes.tsv").exists())
        with self.assertRaises(FileExistsError):
            deploy.prepare(run, request)

    def test_summary_64_bit_cycles_and_pl_logits(self):
        request = self.request()
        run, cycles = self.completed(request)
        result = deploy.summarize(run, request)
        self.assertEqual(result["cycles"], cycles)
        self.assertEqual(result["latency_ms"], cycles / 100000)
        self.assertEqual(result["prediction"], 999)
        self.assertEqual(len(result["int16_logits"]), 1000)
        self.assertEqual(result["numerical_validation"], "NOT_PERFORMED")
        self.assertEqual(result["prediction_source"], "host_argmax_of_PL_logits")

    def test_summary_rejects_bad_evidence(self):
        request = self.request()
        run, _ = self.completed(request)
        for name, data in (
            ("execution_kind.txt", b"MOCK"), ("result.txt", b"RUNNING"),
            ("csr.txt", b"2 1 20 123"), ("csr.txt", b"2 0 5 123"),
            ("csr.txt", b"2 0 20 0"), ("runtime.bin", bytes(16)),
            ("output.bin", bytes(24)), ("input.bin.readback", b"changed"),
            ("hardware/bitstream.bit", b"changed bitstream"),
        ):
            with self.subTest(name=name, data=data):
                path = run / name
                original = path.read_bytes()
                path.write_bytes(data)
                with self.assertRaises(ValueError):
                    deploy.summarize(run, request)
                path.write_bytes(original)

    def test_streaming_comparison(self):
        left, right = self.root / "left", self.root / "right"
        left.write_bytes(b"A" * (1024 * 1024 + 1))
        shutil.copyfile(left, right)
        self.assertTrue(deploy.same_bytes(left, right))
        with right.open("r+b") as stream:
            stream.seek(1024 * 1024)
            stream.write(b"B")
        self.assertFalse(deploy.same_bytes(left, right))

    def batch_request(self):
        request = self.request()
        old = request["files"].pop("input.bin")
        path = Path(old["source"]).with_name("input_bin.bin")
        path.write_bytes(bytes(2 * 401408))
        config = deploy.load_json(deploy.ROOT / "hardware/vgg16_config.json")
        layout = deploy.batch_layout(config, 2)
        request["files"][path.name] = {"source": str(path), "bytes": layout["bytes"],
                                        "ddr_address": layout["ddr_address"]}
        request.update(batch=layout, first_input_word=0x04000040, original_input_address=0x05000000,
                       samples=[{"index": i, "source_image": f"photo{i + 1}.jpg",
                                 "offset": i * 401408, "ddr_address": 0x06000000 + i * 401408}
                                for i in range(2)])
        return request

    def complete_batch_image(self, run, request, index):
        directory = run / "images" / f"{index + 1:04d}"
        directory.mkdir(parents=True)
        cycles = (1 << 32) + index + 1
        (directory / "result.txt").write_text("PASS VGG16 execution")
        (directory / "input_address.txt").write_text(str(request["samples"][index]["ddr_address"]))
        (directory / "csr.txt").write_text(f"2 0 20 {cycles}")
        (directory / "runtime.bin").write_bytes(struct.pack("<QII", cycles, 20, 1))
        logits = [0] * 1000
        logits[index] = 100
        (directory / "output.bin").write_bytes(struct.pack("<1000h", *logits))

    def test_batch_summary_and_input_bank_integrity(self):
        request = self.batch_request()
        run = self.root / "run"
        deploy.prepare(run, request)
        self.assertEqual([int(v) for v in (run / "batch.tsv").read_text().split()],
                         [0x06000000, 802816, 401408, 2, 0x04000040, 0x05000000])
        for name in request["files"]:
            shutil.copyfile(run / "payload" / name, run / f"{name}.readback")
        shutil.copyfile(run / "payload/input_bin.bin", run / "input_bin.bin.final_readback")
        (run / "execution_kind.txt").write_text("HARDWARE")
        (run / "result.txt").write_text("PASS VGG16 execution")
        (run / "restored_input_address.txt").write_text("0x05000000")
        for index in range(2):
            self.complete_batch_image(run, request, index)
        result = deploy.summarize(run, request)
        self.assertEqual(result["start_count"], 2)
        self.assertEqual([r["prediction"] for r in result["images"]], [0, 1])
        self.assertTrue(result["input_bank_unchanged"])
        self.assertEqual(result["timing_ms"]["total"], sum(r["latency_ms"] for r in result["images"]))
        for relative, changed in (("input_bin.bin.final_readback", b"corrupt"),
                                  ("restored_input_address.txt", b"0x06000000"),
                                  ("images/0002/input_address.txt", b"0x06000000"),
                                  ("images/0002/result.txt", b"RUNNING")):
            path = run / relative
            original = path.read_bytes()
            path.write_bytes(changed)
            with self.subTest(relative=relative), self.assertRaises(ValueError):
                deploy.summarize(run, request)
            path.write_bytes(original)

    def test_batch_inputs_reject_corruption_order_addresses_and_overlap(self):
        config = deploy.load_json(deploy.ROOT / "hardware/vgg16_config.json")
        quant = {"model": "VGG16", "format_version": 1, "input_fraction": 0,
                 "preprocessing": config["preprocessing"]}
        photos, model = self.root / "photo", self.root / "model"
        photos.mkdir()
        model.mkdir()
        (model / "quantization.json").write_text(json.dumps(quant), encoding="utf-8")
        for index, color in enumerate(("red", "blue")):
            Image.new("RGB", (250, 250), color).save(photos / f"photo{index + 1}.jpg")
        inputs = self.root / "inputs"
        record = prepare_batch(photos, inputs, model)
        layers = [{"feature_addr": 0x05000000, "input_bytes": 401408,
                   "output_addr": 0x0B000000, "output_bytes": 6422528}]
        self.assertEqual(len(deploy.check_inputs(inputs, quant, config, layers)["samples"]), 2)
        for field, value in (("index", 1), ("offset", 64), ("ddr_address", 0x06062000),
                             ("image", "../outside.png")):
            changed = copy.deepcopy(record)
            changed["samples"][0][field] = value
            (inputs / "batch.json").write_text(json.dumps(changed), encoding="utf-8")
            with self.subTest(field=field), self.assertRaises(ValueError):
                deploy.check_inputs(inputs, quant, config, layers)
        (inputs / "batch.json").write_text(json.dumps(record), encoding="utf-8")
        with self.assertRaises(ValueError):
            deploy.check_inputs(inputs, quant, config, [dict(layers[0], output_addr=0x06000000)])
        path = inputs / "input_bin.bin"
        raw = path.read_bytes()
        path.write_bytes(bytes([raw[0] ^ 1]) + raw[1:])
        with self.assertRaises(ValueError):
            deploy.check_inputs(inputs, quant, config, layers)

    def test_batch_failure_preserves_completed_images(self):
        request = self.batch_request()

        def failed_xsdb(xsdb, arguments, log, timeout):
            run = log.parent
            (run / "execution_kind.txt").write_text("HARDWARE")
            self.complete_batch_image(run, request, 0)
            (run / "result.txt").write_text("FAIL VGG16: image 2 timeout")
            return 1

        with patch.object(deploy, "RUN_DIR", self.root / "failed"), \
                patch.object(deploy, "PREPARE_ONLY", False), \
                patch.object(deploy, "XSDB", Path(__file__)), \
                patch.object(deploy, "preflight", return_value=request), \
                patch.object(deploy, "run_xsdb", side_effect=failed_xsdb), \
                contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(deploy.main(), 1)
            result = deploy.load_json(deploy.RUN_DIR / "summary.json")
            self.assertEqual(result["status"], "FAILED")
            self.assertIn("image 2 timeout", result["reason"])
            self.assertEqual(len(result["completed_images"]), 1)
            self.assertEqual(result["completed_images"][0]["prediction"], 0)

    def test_main_prepare_only_never_launches_xsdb(self):
        request = self.request()
        with patch.object(deploy, "RUN_DIR", self.root / "prepared"), \
                patch.object(deploy, "PREPARE_ONLY", True), \
                patch.object(deploy, "preflight", return_value=request), \
                patch.object(deploy, "run_xsdb", side_effect=AssertionError("must not connect")), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(deploy.main(), 0)
            self.assertEqual(json.loads((deploy.RUN_DIR / "summary.json").read_text())["board_validation"], "NOT_RUN")

    def test_main_failure_is_recorded(self):
        request = self.request()
        with patch.object(deploy, "RUN_DIR", self.root / "failed"), \
                patch.object(deploy, "PREPARE_ONLY", False), \
                patch.object(deploy, "XSDB", Path(__file__)), \
                patch.object(deploy, "preflight", return_value=request), \
                patch.object(deploy, "run_xsdb", side_effect=TimeoutError("test timeout")), \
                contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(deploy.main(), 1)
            self.assertEqual(json.loads((deploy.RUN_DIR / "summary.json").read_text())["status"], "FAILED")

    def test_main_preserves_board_failure_with_any_xsdb_exit_code(self):
        request = self.request()
        failure = "FAIL VGG16: Memory write error at 0x161EC000. Invalid DAP ACK value: 6"

        def failed_xsdb(xsdb, arguments, log, timeout):
            run = log.parent
            (run / "execution_kind.txt").write_text("HARDWARE")
            (run / "result.txt").write_text(failure)
            self.assertEqual(arguments[-1], deploy.JTAG_FREQUENCY_HZ)
            return exit_code

        for exit_code in (0, 1):
            with self.subTest(exit_code=exit_code), \
                    patch.object(deploy, "RUN_DIR", self.root / f"failed_{exit_code}"), \
                    patch.object(deploy, "PREPARE_ONLY", False), \
                    patch.object(deploy, "XSDB", Path(__file__)), \
                    patch.object(deploy, "preflight", return_value=request), \
                    patch.object(deploy, "run_xsdb", side_effect=failed_xsdb), \
                    contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(deploy.main(), 1)
                summary = json.loads((deploy.RUN_DIR / "summary.json").read_text(encoding="utf-8"))
                self.assertIn(failure, summary["reason"])
                self.assertIn(str(deploy.RUN_DIR / "xsdb.log"), summary["reason"])

    def test_tcl_with_mock_hardware(self):
        tclsh = shutil.which("tclsh")
        self.assertIsNotNone(tclsh, "需要 tclsh 执行离线 Tcl 检查")
        result = subprocess.run([tclsh, str(Path(__file__).with_suffix(".tcl")), str(self.root)],
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS VGG Tcl MOCK ONLY", result.stdout)


if __name__ == "__main__":
    unittest.main()
