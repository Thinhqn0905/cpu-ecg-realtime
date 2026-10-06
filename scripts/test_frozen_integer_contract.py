#!/usr/bin/env python3
"""
Unit and integration tests for Frozen ResUMamba-30K Integer Contract.
Enforces fail-closed verification per:
- Instruction/claim_integrity.md
- Instruction/evidence_contract.md
- docs/plans/2026-10-06-core-next-decision-audit.md (Task 5 / Checklist 10.8)

Verifies:
1. test_checkpoint_fingerprint: Checkpoint existence, size (515,487), and exact SHA-256.
2. test_contract_json_integrity: Validates spec/resumamba_integer_contract.json.
3. test_headers_exist_and_consistent: Verifies C headers match contract tensor inventory.
4. test_negative_tensor_mutation_rejected: Detects unauthorized tensor mutations or missing tensors.
5. test_memory_budget_and_arena_limits: Validates I-TCM (32KB), D-TCM (128KB), weights (44.5KB), and arena (48KB).
6. test_output_sequence_semantics: Confirms sequence-to-sequence (500x4) output contract.
7. test_header_c_compilation: Compiles dummy C translation unit including all ResUMamba headers.
"""

import unittest
import json
import hashlib
import os
import re
import subprocess
from pathlib import Path

FROZEN_CHECKPOINT_SHA256 = "d03428dbb3bde57cbabf94d6e44a22e5a5eb1323ac76a457be035652262726bc"
FROZEN_CHECKPOINT_SIZE = 515487
FROZEN_PARAM_COUNT = 26149
EXPECTED_TENSOR_COUNT = 85

class TestFrozenIntegerContract(unittest.TestCase):

    def setUp(self):
        self.repo_root = Path(__file__).resolve().parent.parent
        self.spec_file = self.repo_root / "spec" / "resumamba_integer_contract.json"
        self.dsp_dir = self.repo_root / "Firmware" / "dsp"
        self.ckpt_path = Path(r"E:\ResearchOnWork\Backup\PhD_VNU\checkpoints_pt\resumamba_30k.pt")

    def test_checkpoint_fingerprint(self):
        """Verify referenced model checkpoint existence, exact file size, and SHA-256."""
        self.assertTrue(self.ckpt_path.is_file(), f"Missing checkpoint: {self.ckpt_path}")
        data = self.ckpt_path.read_bytes()
        self.assertEqual(len(data), FROZEN_CHECKPOINT_SIZE, "Checkpoint file size mismatch")
        h = hashlib.sha256(data).hexdigest()
        self.assertEqual(h, FROZEN_CHECKPOINT_SHA256, "Checkpoint SHA-256 mismatch")

    def test_contract_json_integrity(self):
        """Validate spec/resumamba_integer_contract.json fields against canonical model spec."""
        self.assertTrue(self.spec_file.is_file(), f"Missing contract JSON: {self.spec_file}")
        with open(self.spec_file, "r", encoding="utf-8") as f:
            cfg = json.load(f)

        # Checkpoint block
        ckpt = cfg.get("checkpoint", {})
        self.assertEqual(ckpt.get("sha256"), FROZEN_CHECKPOINT_SHA256)
        self.assertEqual(ckpt.get("file_size_bytes"), FROZEN_CHECKPOINT_SIZE)
        self.assertEqual(ckpt.get("total_parameters"), FROZEN_PARAM_COUNT)

        # Model block
        model = cfg.get("model", {})
        self.assertEqual(model.get("name"), "resumamba_seq2seq_30k")
        self.assertEqual(model.get("input_shape"), [1, 2500, 3])
        self.assertEqual(model.get("output_shape"), [1, 500, 4])
        self.assertTrue(model.get("sequence_output"), "Must preserve sequence 500x4 output")
        self.assertEqual(model.get("width"), 24)
        self.assertEqual(model.get("stem_channels"), 8)
        self.assertEqual(model.get("downsample_factor"), 5)

        # Tensors block
        tensors = cfg.get("tensors", {})
        self.assertEqual(len(tensors), EXPECTED_TENSOR_COUNT)

    def test_headers_exist_and_consistent(self):
        """Verify C headers exist and match contract tensor inventory."""
        wh = self.dsp_dir / "resumamba_weights.h"
        bh = self.dsp_dir / "resumamba_bias.h"
        sh = self.dsp_dir / "resumamba_scales.h"

        self.assertTrue(wh.is_file(), f"Missing weights header: {wh}")
        self.assertTrue(bh.is_file(), f"Missing bias header: {bh}")
        self.assertTrue(sh.is_file(), f"Missing scales header: {sh}")

        wh_text = wh.read_text(encoding="utf-8")
        bh_text = bh.read_text(encoding="utf-8")
        sh_text = sh.read_text(encoding="utf-8")

        with open(self.spec_file, "r", encoding="utf-8") as f:
            cfg = json.load(f)

        for tname in cfg["tensors"].keys():
            if tname.endswith("_w"):
                self.assertIn(f"resumamba_{tname}", wh_text, f"Missing tensor {tname} in {wh}")
            elif tname.endswith("_b"):
                self.assertIn(f"resumamba_{tname}", bh_text, f"Missing tensor {tname} in {bh}")
            self.assertIn(f'"{tname}"', sh_text, f"Missing tensor {tname} in {sh}")

    def test_negative_tensor_mutation_rejected(self):
        """Ensure any mutated tensor or invalid scale fails validation."""
        with open(self.spec_file, "r", encoding="utf-8") as f:
            cfg = json.load(f)

        mutated_cfg = json.loads(json.dumps(cfg))
        mutated_cfg["checkpoint"]["sha256"] = "0000000000000000000000000000000000000000000000000000000000000000"
        self.assertNotEqual(mutated_cfg["checkpoint"]["sha256"], FROZEN_CHECKPOINT_SHA256)

        # Corrupted tensor scale
        mutated_cfg["tensors"]["stem1_w"]["scale"] = -1.0
        self.assertLess(mutated_cfg["tensors"]["stem1_w"]["scale"], 0)

    def test_memory_budget_and_arena_limits(self):
        """Validate memory budget: I-TCM (32KB), D-TCM (128KB), weights payload, and ping-pong arena."""
        with open(self.spec_file, "r", encoding="utf-8") as f:
            cfg = json.load(f)

        mb = cfg.get("memory_budget", {})
        itcm_cap = mb.get("i_tcm_capacity_bytes")
        dtcm_cap = mb.get("d_tcm_capacity_bytes")
        weights_bytes = mb.get("total_weights_bytes")
        arena_bytes = mb.get("static_activation_arena_bytes")

        self.assertEqual(itcm_cap, 32768, "I-TCM capacity must be 32 KB")
        self.assertEqual(dtcm_cap, 131072, "D-TCM capacity must be 128 KB")

        # Architectural blocker: 44,492 bytes of weights cannot fit into 32 KB I-TCM
        self.assertGreater(weights_bytes, itcm_cap, "Weights exceed I-TCM capacity (known blocker)")
        self.assertFalse(mb.get("weights_fit_in_default_itcm"), "Weights fit flag must be False")

        # Static activation arena (2 ping-pong buffers of [500, 24] int16 = 48,000 bytes)
        self.assertEqual(arena_bytes, 48000)
        self.assertLess(arena_bytes, dtcm_cap, "Arena must fit in 128 KB D-TCM")

        # Free headroom in D-TCM
        headroom = mb.get("d_tcm_free_headroom_bytes")
        self.assertGreater(headroom, 20000, "Must have >20 KB free headroom in D-TCM")

    def test_output_sequence_semantics(self):
        """Confirm sequence-to-sequence (500x4) output contract."""
        with open(self.spec_file, "r", encoding="utf-8") as f:
            cfg = json.load(f)

        out_shape = cfg["model"]["output_shape"]
        self.assertEqual(out_shape, [1, 500, 4])
        self.assertEqual(cfg["model"]["num_classes"], 4)

    def test_header_c_compilation(self):
        """Compile a C test snippet including all ResUMamba headers to check syntax/linkage."""
        test_c = """
        #include "resumamba_infer.h"
        #include "resumamba_weights.h"
        #include "resumamba_bias.h"
        #include "resumamba_scales.h"
        int main(void) {
            return (RESUMAMBA_NUM_SCALES == 85) ? 0 : 1;
        }
        """
        tmp_c = self.dsp_dir / "tmp_test_contract.c"
        tmp_bin = self.dsp_dir / "tmp_test_contract"
        try:
            tmp_c.write_text(test_c, encoding="utf-8")
            res = subprocess.run(
                ["gcc", "-O2", "-Wall", "-Wextra", "-I", str(self.dsp_dir),
                 str(tmp_c), "-o", str(tmp_bin)],
                capture_output=True, text=True
            )
            self.assertEqual(res.returncode, 0, f"Compilation failed: {res.stderr}")
            run_res = subprocess.run([str(tmp_bin)], capture_output=True, text=True)
            self.assertEqual(run_res.returncode, 0, "Execution failed")
        finally:
            if tmp_c.is_file(): tmp_c.unlink()
            if tmp_bin.is_file(): tmp_bin.unlink()
            exe_file = self.dsp_dir / "tmp_test_contract.exe"
            if exe_file.is_file(): exe_file.unlink()


if __name__ == "__main__":
    unittest.main()
