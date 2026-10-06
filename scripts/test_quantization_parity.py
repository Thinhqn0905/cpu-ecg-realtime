#!/usr/bin/env python3
# Copyright 2026 RISC-V ECG Project
# SPDX-License-Identifier: Apache-2.0
"""
Test numerical parity between FP32 ResUMamba-30K and INT8/INT16 quantized firmware tables.
Verifies:
1. Firmware weight header files exist and are non-empty:
   - Firmware/dsp/resumamba_weights.h
   - Firmware/dsp/resumamba_bias.h
2. Quantized model reproduces FP32 predictions on synthetic ECG traces:
   - Max Absolute Error (MAE) < 0.05
   - Argmax classification parity >= 98.0%
"""

import os
import sys
import numpy as np

def generate_synthetic_ecg(samples=2500, channels=3, seed=42):
    """Generate realistic synthetic 3-lead ECG trace with cardiac pulses."""
    np.random.seed(seed)
    t = np.linspace(0, 10, samples) # 10 seconds @ 250 Hz
    leads = []
    for ch in range(channels):
        # Baseline wander (0.15 Hz) + respiration (0.3 Hz)
        wander = 0.2 * np.sin(2 * np.pi * 0.15 * t + ch)
        # R-peaks at ~72 bpm (1.2 Hz)
        cardiac = np.zeros(samples)
        beat_interval = int(250 / 1.2) # ~208 samples
        for idx in range(100, samples - 50, beat_interval):
            # QRS complex: Q dip, R spike, S dip
            cardiac[idx - 5] = -0.15 * (1.0 + 0.2 * ch)
            cardiac[idx]     =  1.50 * (1.0 - 0.1 * ch) # R-peak
            cardiac[idx + 5] = -0.25 * (1.0 + 0.1 * ch)
        noise = 0.02 * np.random.randn(samples)
        sig = wander + cardiac + noise
        # Normalize per-lead Z-score
        sig = (sig - np.mean(sig)) / (np.std(sig) + 1e-6)
        leads.append(sig)
    return np.stack(leads, axis=-1) # (samples, channels)

def main():
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    weights_header = os.path.join(root_dir, "Firmware", "dsp", "resumamba_weights.h")
    bias_header = os.path.join(root_dir, "Firmware", "dsp", "resumamba_bias.h")
    checkpoint_path = r"E:\ResearchOnWork\Backup\PhD_VNU\checkpoints_pt\resumamba_30k.pt"

    print("================================================================")
    print("  RESUMAMBA-30K INT8/INT16 QUANTIZATION PARITY VERIFICATION")
    print("================================================================")

    # Gate 1: Check header existence
    if not os.path.exists(weights_header) or not os.path.exists(bias_header):
        print(f"[FAIL] Missing quantized header files: {weights_header} or {bias_header}")
        print("Run scripts/quantize_resumamba.py first to generate firmware tables.")
        sys.exit(1)

    # Gate 2: Load PyTorch FP32 model
    sys.path.append(r"E:\ResearchOnWork\Backup\PhD_VNU")
    import torch
    from ecgr_torch.model import load_pt

    print(f"[1/3] Loading FP32 reference model: {checkpoint_path}")
    model_fp32, spec = load_pt(checkpoint_path)
    model_fp32.eval()

    # Gate 3: Run synthetic trace
    ecg_data = generate_synthetic_ecg(samples=2500, channels=3)
    x_tensor = torch.tensor(ecg_data[np.newaxis, :, :], dtype=torch.float32)

    with torch.no_grad():
        out_fp32 = model_fp32(x_tensor).numpy()[0] # (500, 4)

    # Gate 4: Load and simulate quantized forward pass
    from quantize_resumamba import simulate_quantized_forward
    print("[2/3] Simulating INT8/INT16 quantized model execution...")
    out_q = simulate_quantized_forward(ecg_data, weights_header, bias_header)

    mae = np.max(np.abs(out_fp32 - out_q))
    pred_fp32 = np.argmax(out_fp32, axis=-1)
    pred_q    = np.argmax(out_q, axis=-1)
    parity    = np.mean(pred_fp32 == pred_q) * 100.0

    print("[3/3] Evaluating Parity Metrics:")
    print(f"      - Max Absolute Probability Error: {mae:.5f} (Threshold < 0.05)")
    print(f"      - Argmax Prediction Parity:      {parity:.2f}% (Threshold >= 98.0%)")

    if mae < 0.05 and parity >= 98.0:
        print("[PASS] Quantization parity verified within clinical tolerance!")
        sys.exit(0)
    else:
        print("[FAIL] Quantization error exceeds tolerance limits!")
        sys.exit(1)

if __name__ == "__main__":
    main()
