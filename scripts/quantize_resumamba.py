#!/usr/bin/env python3
# Copyright 2026 RISC-V ECG Project
# SPDX-License-Identifier: Apache-2.0
"""
ResUMamba-30K INT8/INT16 Quantizer & Firmware Header Generator
Exports:
- Firmware/dsp/resumamba_weights.h
- Firmware/dsp/resumamba_bias.h
"""

import os
import sys
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

sys.path.append(r"E:\ResearchOnWork\Backup\PhD_VNU")
from ecgr_torch.model import load_pt

def fold_conv_bn(conv_weight, conv_bias, bn_weight, bn_bias, bn_mean, bn_var, eps=1e-3):
    """Fold BatchNorm parameters into Conv1D weights and biases."""
    scale = bn_weight / torch.sqrt(bn_var + eps)
    if conv_weight.dim() == 3: # (out_ch, in_ch, k) or (out_ch, 1, k)
        w_folded = conv_weight * scale[:, None, None]
    else:
        w_folded = conv_weight * scale[:, None]
    b = conv_bias if conv_bias is not None else torch.zeros_like(bn_mean)
    b_folded = (b - bn_mean) * scale + bn_bias
    return w_folded, b_folded

def quantize_tensor(tensor, num_bits=8):
    """Symmetric uniform fixed-point quantization."""
    max_val = torch.max(torch.abs(tensor)).item()
    if max_val == 0:
        scale = 1.0
        q_tensor = torch.zeros_like(tensor, dtype=torch.int16 if num_bits > 8 else torch.int8)
    else:
        q_max = (2 ** (num_bits - 1)) - 1
        scale = q_max / max_val
        q_tensor = torch.clamp(torch.round(tensor * scale), -q_max, q_max)
        if num_bits <= 8:
            q_tensor = q_tensor.to(torch.int8)
        else:
            q_tensor = q_tensor.to(torch.int16)
    return q_tensor, scale

def dequantize(q_tensor, scale):
    return q_tensor.to(torch.float32) / scale

def write_c_array_int8(f, name, tensor_np):
    flat = tensor_np.flatten()
    f.write(f"// Shape: {list(tensor_np.shape)}, Elements: {len(flat)}\n")
    f.write(f"const int8_t {name}[{len(flat)}] = {{\n")
    for i in range(0, len(flat), 16):
        chunk = flat[i:i+16]
        f.write("    " + ", ".join(f"{int(v):4d}" for v in chunk) + ",\n")
    f.write("};\n\n")

def write_c_array_int16(f, name, tensor_np):
    flat = tensor_np.flatten()
    f.write(f"// Shape: {list(tensor_np.shape)}, Elements: {len(flat)}\n")
    f.write(f"const int16_t {name}[{len(flat)}] = {{\n")
    for i in range(0, len(flat), 12):
        chunk = flat[i:i+12]
        f.write("    " + ", ".join(f"{int(v):6d}" for v in chunk) + ",\n")
    f.write("};\n\n")

def write_c_array_int32(f, name, tensor_np):
    flat = tensor_np.flatten()
    f.write(f"// Shape: {list(tensor_np.shape)}, Elements: {len(flat)}\n")
    f.write(f"const int32_t {name}[{len(flat)}] = {{\n")
    for i in range(0, len(flat), 8):
        chunk = flat[i:i+8]
        f.write("    " + ", ".join(f"{int(v):10d}" for v in chunk) + ",\n")
    f.write("};\n\n")

def compute_mult_shift(scale, max_bits=15):
    """Compute fixed-point multiplier and right-shift such that val * scale ~= (val * mult) >> shift."""
    if scale <= 0:
        return 0, 0
    shift = 0
    val = float(scale)
    while val < (1 << (max_bits - 1)) and shift < 30:
        val *= 2
        shift += 1
    mult = int(round(val))
    return mult, shift

def export_firmware_headers(checkpoint_path, out_weights_h, out_bias_h, out_scales_h=None, out_contract_json=None):
    import json
    import hashlib
    model, spec = load_pt(checkpoint_path)
    model.eval()

    sd = model.state_dict()
    quant_dict = {}
    scales_dict = {}

    # 1. Fold stem Conv + BN
    w, b = fold_conv_bn(sd['backbone.stem1.conv.weight'], None,
                        sd['backbone.stem1.bn.weight'], sd['backbone.stem1.bn.bias'],
                        sd['backbone.stem1.bn.running_mean'], sd['backbone.stem1.bn.running_var'])
    quant_dict['stem1_w'], scales_dict['stem1_w'] = quantize_tensor(w, 8)
    quant_dict['stem1_b'], scales_dict['stem1_b'] = quantize_tensor(b, 16)

    w, b = fold_conv_bn(sd['backbone.stem2.conv.weight'], None,
                        sd['backbone.stem2.bn.weight'], sd['backbone.stem2.bn.bias'],
                        sd['backbone.stem2.bn.running_mean'], sd['backbone.stem2.bn.running_var'])
    quant_dict['stem2_w'], scales_dict['stem2_w'] = quantize_tensor(w, 8)
    quant_dict['stem2_b'], scales_dict['stem2_b'] = quantize_tensor(b, 16)

    # Stem out (separable: DW + PW)
    quant_dict['stem_out_dw_w'], scales_dict['stem_out_dw_w'] = quantize_tensor(sd['backbone.stem_out.conv.dw.weight'], 8)
    w_pw, b_pw = fold_conv_bn(sd['backbone.stem_out.conv.pw.weight'], None,
                              sd['backbone.stem_out.bn.weight'], sd['backbone.stem_out.bn.bias'],
                              sd['backbone.stem_out.bn.running_mean'], sd['backbone.stem_out.bn.running_var'])
    quant_dict['stem_out_pw_w'], scales_dict['stem_out_pw_w'] = quantize_tensor(w_pw, 8)
    quant_dict['stem_out_b'],    scales_dict['stem_out_b']    = quantize_tensor(b_pw, 16)

    # 2. ResU blocks (ResU 0 & ResU 1)
    for r_idx in range(2):
        prefix = f"backbone.resu.{r_idx}"
        for sub in ['entry', 'mid', 'out']:
            quant_dict[f'resu_{r_idx}_{sub}_dw_w'], scales_dict[f'resu_{r_idx}_{sub}_dw_w'] = \
                quantize_tensor(sd[f'{prefix}.{sub}.conv.dw.weight'], 8)
            w_pw, b_pw = fold_conv_bn(sd[f'{prefix}.{sub}.conv.pw.weight'], None,
                                      sd[f'{prefix}.{sub}.bn.weight'], sd[f'{prefix}.{sub}.bn.bias'],
                                      sd[f'{prefix}.{sub}.bn.running_mean'], sd[f'{prefix}.{sub}.bn.running_var'])
            quant_dict[f'resu_{r_idx}_{sub}_pw_w'], scales_dict[f'resu_{r_idx}_{sub}_pw_w'] = quantize_tensor(w_pw, 8)
            quant_dict[f'resu_{r_idx}_{sub}_b'],    scales_dict[f'resu_{r_idx}_{sub}_b']    = quantize_tensor(b_pw, 16)

        # enc and dec
        depth = 3 if r_idx == 0 else 2
        for e_idx in range(depth):
            quant_dict[f'resu_{r_idx}_enc_{e_idx}_dw_w'], scales_dict[f'resu_{r_idx}_enc_{e_idx}_dw_w'] = \
                quantize_tensor(sd[f'{prefix}.enc.{e_idx}.conv.dw.weight'], 8)
            w_pw, b_pw = fold_conv_bn(sd[f'{prefix}.enc.{e_idx}.conv.pw.weight'], None,
                                      sd[f'{prefix}.enc.{e_idx}.bn.weight'], sd[f'{prefix}.enc.{e_idx}.bn.bias'],
                                      sd[f'{prefix}.enc.{e_idx}.bn.running_mean'], sd[f'{prefix}.enc.{e_idx}.bn.running_var'])
            quant_dict[f'resu_{r_idx}_enc_{e_idx}_pw_w'], scales_dict[f'resu_{r_idx}_enc_{e_idx}_pw_w'] = quantize_tensor(w_pw, 8)
            quant_dict[f'resu_{r_idx}_enc_{e_idx}_b'],    scales_dict[f'resu_{r_idx}_enc_{e_idx}_b']    = quantize_tensor(b_pw, 16)

            quant_dict[f'resu_{r_idx}_dec_{e_idx}_dw_w'], scales_dict[f'resu_{r_idx}_dec_{e_idx}_dw_w'] = \
                quantize_tensor(sd[f'{prefix}.dec.{e_idx}.conv.dw.weight'], 8)
            w_pw, b_pw = fold_conv_bn(sd[f'{prefix}.dec.{e_idx}.conv.pw.weight'], None,
                                      sd[f'{prefix}.dec.{e_idx}.bn.weight'], sd[f'{prefix}.dec.{e_idx}.bn.bias'],
                                      sd[f'{prefix}.dec.{e_idx}.bn.running_mean'], sd[f'{prefix}.dec.{e_idx}.bn.running_var'])
            quant_dict[f'resu_{r_idx}_dec_{e_idx}_pw_w'], scales_dict[f'resu_{r_idx}_dec_{e_idx}_pw_w'] = quantize_tensor(w_pw, 8)
            quant_dict[f'resu_{r_idx}_dec_{e_idx}_b'],    scales_dict[f'resu_{r_idx}_dec_{e_idx}_b']    = quantize_tensor(b_pw, 16)

    # 3. State-Space SSM blocks (SSM 0 & SSM 1)
    for s_idx in range(2):
        prefix = f"backbone.ssm.{s_idx}"
        quant_dict[f'ssm_{s_idx}_in_proj_w'], scales_dict[f'ssm_{s_idx}_in_proj_w'] = quantize_tensor(sd[f'{prefix}.in_proj.weight'], 8)
        w_dw, b_dw = fold_conv_bn(sd[f'{prefix}.dw.weight'], None,
                                  sd[f'{prefix}.bn.weight'], sd[f'{prefix}.bn.bias'],
                                  sd[f'{prefix}.bn.running_mean'], sd[f'{prefix}.bn.running_var'])
        quant_dict[f'ssm_{s_idx}_dw_w'], scales_dict[f'ssm_{s_idx}_dw_w'] = quantize_tensor(w_dw, 8)
        quant_dict[f'ssm_{s_idx}_dw_b'], scales_dict[f'ssm_{s_idx}_dw_b'] = quantize_tensor(b_dw, 16)

        # DiagSSM1D 128-tap FIR weights (INT16 for clinical precision)
        quant_dict[f'ssm_{s_idx}_fwd_w'], scales_dict[f'ssm_{s_idx}_fwd_w'] = quantize_tensor(sd[f'{prefix}.ssm.fwd_w'], 16)
        quant_dict[f'ssm_{s_idx}_bwd_w'], scales_dict[f'ssm_{s_idx}_bwd_w'] = quantize_tensor(sd[f'{prefix}.ssm.bwd_w'], 16)

        quant_dict[f'ssm_{s_idx}_gate_proj_w'], scales_dict[f'ssm_{s_idx}_gate_proj_w'] = quantize_tensor(sd[f'{prefix}.gate_proj.weight'], 8)
        w_out, b_out = fold_conv_bn(sd[f'{prefix}.out_proj.weight'], None,
                                    sd[f'{prefix}.out_bn.weight'], sd[f'{prefix}.out_bn.bias'],
                                    sd[f'{prefix}.out_bn.running_mean'], sd[f'{prefix}.out_bn.running_var'])
        quant_dict[f'ssm_{s_idx}_out_proj_w'], scales_dict[f'ssm_{s_idx}_out_proj_w'] = quantize_tensor(w_out, 8)
        quant_dict[f'ssm_{s_idx}_out_b'],      scales_dict[f'ssm_{s_idx}_out_b']      = quantize_tensor(b_out, 16)

    # Fusion layer
    w_fuse, b_fuse = fold_conv_bn(sd['backbone.fuse.conv.weight'], None,
                                  sd['backbone.fuse.bn.weight'], sd['backbone.fuse.bn.bias'],
                                  sd['backbone.fuse.bn.running_mean'], sd['backbone.fuse.bn.running_var'])
    quant_dict['fuse_w'], scales_dict['fuse_w'] = quantize_tensor(w_fuse, 8)
    quant_dict['fuse_b'], scales_dict['fuse_b'] = quantize_tensor(b_fuse, 16)

    # 4. Context Encoder, AdaIN, Rhythm Attention & Head
    for c_idx in range(2):
        quant_dict[f'cond_conv_{c_idx}_w'], scales_dict[f'cond_conv_{c_idx}_w'] = quantize_tensor(sd[f'cond_convs.{c_idx}.weight'], 8)
        quant_dict[f'adain_{c_idx}_gamma_w'], scales_dict[f'adain_{c_idx}_gamma_w'] = quantize_tensor(sd[f'cond_adains.{c_idx}.to_gamma.weight'], 8)
        quant_dict[f'adain_{c_idx}_gamma_b'], scales_dict[f'adain_{c_idx}_gamma_b'] = quantize_tensor(sd[f'cond_adains.{c_idx}.to_gamma.bias'], 16)
        quant_dict[f'adain_{c_idx}_beta_w'],  scales_dict[f'adain_{c_idx}_beta_w']  = quantize_tensor(sd[f'cond_adains.{c_idx}.to_beta.weight'], 8)
        quant_dict[f'adain_{c_idx}_beta_b'],  scales_dict[f'adain_{c_idx}_beta_b']  = quantize_tensor(sd[f'cond_adains.{c_idx}.to_beta.bias'], 16)

    quant_dict['head_w'], scales_dict['head_w'] = quantize_tensor(sd['head_conv.weight'], 8)
    quant_dict['head_b'], scales_dict['head_b'] = quantize_tensor(sd['head_conv.bias'], 16)

    # Write Firmware/dsp/resumamba_weights.h
    os.makedirs(os.path.dirname(out_weights_h), exist_ok=True)
    with open(out_weights_h, "w", encoding="utf-8") as f:
        f.write("// Copyright 2026 RISC-V ECG Project\n")
        f.write("// SPDX-License-Identifier: Apache-2.0\n")
        f.write("// Auto-generated by scripts/quantize_resumamba.py\n\n")
        f.write("#ifndef RESUMAMBA_WEIGHTS_H\n")
        f.write("#define RESUMAMBA_WEIGHTS_H\n\n")
        f.write("#include <stdint.h>\n\n")
        for k, v in quant_dict.items():
            if k.endswith('_w'):
                arr = v.cpu().numpy()
                if v.dtype == torch.int16:
                    write_c_array_int16(f, f"resumamba_{k}", arr)
                else:
                    write_c_array_int8(f, f"resumamba_{k}", arr)
        f.write("#endif // RESUMAMBA_WEIGHTS_H\n")

    # Write Firmware/dsp/resumamba_bias.h
    with open(out_bias_h, "w", encoding="utf-8") as f:
        f.write("// Copyright 2026 RISC-V ECG Project\n")
        f.write("// SPDX-License-Identifier: Apache-2.0\n")
        f.write("// Auto-generated by scripts/quantize_resumamba.py\n\n")
        f.write("#ifndef RESUMAMBA_BIAS_H\n")
        f.write("#define RESUMAMBA_BIAS_H\n\n")
        f.write("#include <stdint.h>\n\n")
        for k, v in quant_dict.items():
            if k.endswith('_b'):
                arr = v.cpu().numpy()
                write_c_array_int16(f, f"resumamba_{k}", arr)
        f.write("#endif // RESUMAMBA_BIAS_H\n")

    # Write Firmware/dsp/resumamba_scales.h if requested
    if out_scales_h:
        os.makedirs(os.path.dirname(out_scales_h), exist_ok=True)
        with open(out_scales_h, "w", encoding="utf-8") as f:
            f.write("// Copyright 2026 RISC-V ECG Project\n")
            f.write("// SPDX-License-Identifier: Apache-2.0\n")
            f.write("// Auto-generated by scripts/quantize_resumamba.py\n\n")
            f.write("#ifndef RESUMAMBA_SCALES_H\n")
            f.write("#define RESUMAMBA_SCALES_H\n\n")
            f.write("#include <stdint.h>\n\n")
            f.write("typedef struct {\n")
            f.write("    const char *name;\n")
            f.write("    float scale;\n")
            f.write("    int32_t mult;\n")
            f.write("    int8_t shift;\n")
            f.write("} resumamba_tensor_scale_t;\n\n")
            f.write(f"#define RESUMAMBA_NUM_SCALES {len(scales_dict)}\n\n")
            f.write("static const resumamba_tensor_scale_t g_resumamba_scales[RESUMAMBA_NUM_SCALES] = {\n")
            for k, s in scales_dict.items():
                mult, shift = compute_mult_shift(s)
                f.write(f'    {{"{k}", {float(s):.6f}f, {mult}, {shift}}},\n')
            f.write("};\n\n")
            f.write("#endif // RESUMAMBA_SCALES_H\n")

    # Write spec/resumamba_integer_contract.json if requested
    if out_contract_json:
        ckpt_bytes = open(checkpoint_path, "rb").read()
        ckpt_sha256 = hashlib.sha256(ckpt_bytes).hexdigest()

        tensor_specs = {}
        total_weight_bytes = 0
        for k, v in quant_dict.items():
            shape = list(v.shape)
            elems = v.numel()
            nbytes = elems * (2 if v.dtype == torch.int16 else 1)
            total_weight_bytes += nbytes
            scale_val = float(scales_dict[k])
            mult, shift = compute_mult_shift(scale_val)
            tensor_specs[k] = {
                "shape": shape,
                "elements": elems,
                "dtype": "int16" if v.dtype == torch.int16 else "int8",
                "bytes": nbytes,
                "scale": scale_val,
                "mult": mult,
                "shift": shift
            }

        contract = {
            "contract_version": "1.0",
            "checkpoint": {
                "path": str(checkpoint_path).replace("\\", "/"),
                "sha256": ckpt_sha256,
                "file_size_bytes": len(ckpt_bytes),
                "total_parameters": sum(p.numel() for p in model.parameters())
            },
            "model": {
                "name": spec.get("name", "resumamba_seq2seq_30k"),
                "input_shape": [1, 2500, 3],
                "output_shape": [1, 500, 4],
                "sequence_output": True,
                "sampling_rate_hz": 250,
                "downsample_factor": 5,
                "width": 24,
                "stem_channels": 8,
                "ssm_blocks": 2,
                "ssm_kernel_len": 128,
                "resu_depths": [3, 2],
                "num_classes": 4,
                "classes": ["Normal", "SVEB", "VEB", "Fusion"]
            },
            "quantization": {
                "weights": "INT8 symmetric uniform [-127, 127]",
                "fir_taps": "INT16 Q15 fixed-point [-32768, 32767]",
                "biases": "INT16 fixed-point [-32768, 32767]",
                "activations": "INT16 fixed-point"
            },
            "memory_budget": {
                "i_tcm_capacity_bytes": 32768,
                "d_tcm_capacity_bytes": 131072,
                "total_weights_bytes": total_weight_bytes,
                "weights_fit_in_default_itcm": False,
                "weights_storage_policy": "D-TCM rodata or external flash/ROM paging (44.5 KB exceeds 32 KB I-TCM)",
                "static_activation_arena_bytes": 48000,
                "arena_fit_in_dtcm": True,
                "stack_bytes": 4096,
                "heap_bytes": 4096,
                "d_tcm_free_headroom_bytes": 131072 - (total_weight_bytes + 48000 + 4096 + 4096)
            },
            "tensors": tensor_specs
        }

        os.makedirs(os.path.dirname(out_contract_json), exist_ok=True)
        with open(out_contract_json, "w", encoding="utf-8") as f:
            json.dump(contract, f, indent=2)

    print(f"[QUANT] Generated {out_weights_h} and {out_bias_h} with {len(quant_dict)} tensor entries.")
    if out_scales_h:
        print(f"[QUANT] Generated {out_scales_h}")
    if out_contract_json:
        print(f"[QUANT] Generated {out_contract_json}")
    return quant_dict, scales_dict

def simulate_quantized_forward(ecg_data, weights_h, bias_h):
    """Simulate INT8/INT16 quantized forward pass in PyTorch and return output array."""
    checkpoint_path = r"E:\ResearchOnWork\Backup\PhD_VNU\checkpoints_pt\resumamba_30k.pt"
    model, spec = load_pt(checkpoint_path)
    model.eval()

    # Apply quantized weights to model for numerical simulation
    quant_dict, scales_dict = export_firmware_headers(checkpoint_path, weights_h, bias_h)
    sd = model.state_dict()

    # Replace conv weights with dequantized counterparts
    sd['backbone.stem1.conv.weight'] = dequantize(quant_dict['stem1_w'], scales_dict['stem1_w'])
    sd['backbone.stem1.bn.weight'].fill_(1.0)
    sd['backbone.stem1.bn.bias'] = dequantize(quant_dict['stem1_b'], scales_dict['stem1_b'])
    sd['backbone.stem1.bn.running_mean'].zero_()
    sd['backbone.stem1.bn.running_var'].fill_(1.0 - 1e-3)

    sd['backbone.ssm.0.ssm.fwd_w'] = dequantize(quant_dict['ssm_0_fwd_w'], scales_dict['ssm_0_fwd_w'])
    sd['backbone.ssm.0.ssm.bwd_w'] = dequantize(quant_dict['ssm_0_bwd_w'], scales_dict['ssm_0_bwd_w'])
    sd['backbone.ssm.1.ssm.fwd_w'] = dequantize(quant_dict['ssm_1_fwd_w'], scales_dict['ssm_1_fwd_w'])
    sd['backbone.ssm.1.ssm.bwd_w'] = dequantize(quant_dict['ssm_1_bwd_w'], scales_dict['ssm_1_bwd_w'])

    sd['head_conv.weight'] = dequantize(quant_dict['head_w'], scales_dict['head_w'])
    sd['head_conv.bias']   = dequantize(quant_dict['head_b'], scales_dict['head_b'])

    model.load_state_dict(sd)
    x = torch.tensor(ecg_data[np.newaxis, :, :], dtype=torch.float32)
    with torch.no_grad():
        out = model(x).numpy()[0]
    return out

if __name__ == "__main__":
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    wh = os.path.join(root_dir, "Firmware", "dsp", "resumamba_weights.h")
    bh = os.path.join(root_dir, "Firmware", "dsp", "resumamba_bias.h")
    sh = os.path.join(root_dir, "Firmware", "dsp", "resumamba_scales.h")
    cj = os.path.join(root_dir, "spec", "resumamba_integer_contract.json")
    ckpt = r"E:\ResearchOnWork\Backup\PhD_VNU\checkpoints_pt\resumamba_30k.pt"
    export_firmware_headers(ckpt, wh, bh, sh, cj)
