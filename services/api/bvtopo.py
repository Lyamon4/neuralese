#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
TopoFuse-style benchmark for LeNet-5 (MNIST-like).
Compares:
  1) Baseline: N separate LeNet-5 models, sequential forward/backward (single optimizer step for fairness).
  2) Fused/TopoFuse: one banked LeNet-5 with parameters stacked along "user" dimension,
     grouped convolution + batched matmul (single forward/backward, single optimizer step).

Outputs:
  - Verbose table to stdout
  - CSV results (default: results_lenet5_topofuse.csv)

This is designed to measure the "scaling benefit with more users" (N on X axis).
"""

import argparse
import csv

import math
import os
import time
from dataclasses import dataclass
from typing import Dict, List, Tuple, Optional

import torch
import torch.nn as nn
import torch.nn.functional as F


# ----------------------------
# Model: classic LeNet-5
# ----------------------------
class LeNet5(nn.Module):
    """
    LeNet-5 style for 32x32 inputs (MNIST padded to 32x32).
    conv1: 1->6, k=5 => 28x28
    pool => 14x14
    conv2: 6->16, k=5 => 10x10
    pool => 5x5
    fc1: 16*5*5=400 -> 120
    fc2: 120 -> 84
    fc3: 84 -> 10
    """
    def __init__(self):
        super().__init__()
        self.conv1 = nn.Conv2d(1, 6, kernel_size=5, stride=1, padding=0)
        self.conv2 = nn.Conv2d(6, 16, kernel_size=5, stride=1, padding=0)
        self.fc1 = nn.Linear(16 * 5 * 5, 120)
        self.fc2 = nn.Linear(120, 84)
        self.fc3 = nn.Linear(84, 10)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = F.relu(self.conv1(x))
        x = F.avg_pool2d(x, kernel_size=2, stride=2)
        x = F.relu(self.conv2(x))
        x = F.avg_pool2d(x, kernel_size=2, stride=2)
        x = x.flatten(1)
        x = F.relu(self.fc1(x))
        x = F.relu(self.fc2(x))
        x = self.fc3(x)
        return x


# ----------------------------
# Model: banked / fused LeNet-5
# ----------------------------
class BankedLeNet5(nn.Module):
    """
    Parameters are stacked for N users:
      conv1_w: (N, 6, 1, 5, 5)  conv1_b: (N, 6)
      conv2_w: (N,16, 6, 5, 5)  conv2_b: (N,16)
      fc1_w:   (N,120,400)      fc1_b:   (N,120)
      fc2_w:   (N, 84,120)      fc2_b:   (N, 84)
      fc3_w:   (N, 10, 84)      fc3_b:   (N, 10)

    Fused execution:
      - inputs: (N, B, 1, 32, 32)
      - conv uses grouped conv with groups=N
      - linears use batched matmul (bmm)
    """
    def __init__(self, n_users: int, device: torch.device, dtype: torch.dtype):
        super().__init__()
        self.n = n_users
        self.device = device
        self.dtype = dtype

        # conv1
        self.conv1_w = nn.Parameter(torch.empty((n_users, 6, 1, 5, 5), device=device, dtype=dtype))
        self.conv1_b = nn.Parameter(torch.empty((n_users, 6), device=device, dtype=dtype))

        # conv2
        self.conv2_w = nn.Parameter(torch.empty((n_users, 16, 6, 5, 5), device=device, dtype=dtype))
        self.conv2_b = nn.Parameter(torch.empty((n_users, 16), device=device, dtype=dtype))

        # fc
        self.fc1_w = nn.Parameter(torch.empty((n_users, 120, 400), device=device, dtype=dtype))
        self.fc1_b = nn.Parameter(torch.empty((n_users, 120), device=device, dtype=dtype))

        self.fc2_w = nn.Parameter(torch.empty((n_users, 84, 120), device=device, dtype=dtype))
        self.fc2_b = nn.Parameter(torch.empty((n_users, 84), device=device, dtype=dtype))

        self.fc3_w = nn.Parameter(torch.empty((n_users, 10, 84), device=device, dtype=dtype))
        self.fc3_b = nn.Parameter(torch.empty((n_users, 10), device=device, dtype=dtype))

        self.reset_parameters()

    def reset_parameters(self):
        # Kaiming init-ish for conv/linear weights; zeros for bias
        for w in [self.conv1_w, self.conv2_w]:
            nn.init.kaiming_uniform_(w.view(-1, *w.shape[2:]), a=math.sqrt(5))
        for b in [self.conv1_b, self.conv2_b]:
            nn.init.zeros_(b)

        for w in [self.fc1_w, self.fc2_w, self.fc3_w]:
            nn.init.kaiming_uniform_(w.view(-1, w.shape[-1]), a=math.sqrt(5))
        for b in [self.fc1_b, self.fc2_b, self.fc3_b]:
            nn.init.zeros_(b)

    def forward(self, x_nbhw: torch.Tensor) -> torch.Tensor:
        """
        x_nbhw: (N, B, 1, 32, 32)
        returns logits: (N, B, 10)
        """
        N, B, C, H, W = x_nbhw.shape
        assert N == self.n and C == 1 and H == 32 and W == 32

        # Pack users into channel dimension for grouped conv:
        # (N,B,1,H,W) -> (B, N*1, H, W)
        x = x_nbhw.permute(1, 0, 2, 3, 4).contiguous().view(B, N * 1, H, W)

        # conv1 grouped: weight (N*6, 1, 5, 5), groups=N
        w1 = self.conv1_w.contiguous().view(N * 6, 1, 5, 5)
        b1 = self.conv1_b.contiguous().view(N * 6)
        x = F.conv2d(x, w1, b1, stride=1, padding=0, groups=N)
        x = F.relu(x)
        x = F.avg_pool2d(x, kernel_size=2, stride=2)

        # conv2 grouped: input channels N*6, weight (N*16, 6, 5, 5), groups=N
        w2 = self.conv2_w.contiguous().view(N * 16, 6, 5, 5)
        b2 = self.conv2_b.contiguous().view(N * 16)
        x = F.conv2d(x, w2, b2, stride=1, padding=0, groups=N)
        x = F.relu(x)
        x = F.avg_pool2d(x, kernel_size=2, stride=2)  # -> (B, N*16, 5, 5)

        # Unpack back to (N,B,features)
        x = x.view(B, N, 16, 5, 5).permute(1, 0, 2, 3, 4).contiguous()  # (N,B,16,5,5)
        x = x.view(N, B, 16 * 5 * 5)  # (N,B,400)

        # Batched linears: (N,B,in) x (N,in,out) => (N,B,out)
        # Use bmm: (N,B,in) @ (N,in,out)
        x = torch.bmm(x, self.fc1_w.transpose(1, 2)) + self.fc1_b.unsqueeze(1)
        x = F.relu(x)

        x = torch.bmm(x, self.fc2_w.transpose(1, 2)) + self.fc2_b.unsqueeze(1)
        x = F.relu(x)

        x = torch.bmm(x, self.fc3_w.transpose(1, 2)) + self.fc3_b.unsqueeze(1)
        return x  # (N,B,10)


# ----------------------------
# Benchmark infra
# ----------------------------
@dataclass
class RunStats:
    avg_step_ms: float
    p50_step_ms: float
    p90_step_ms: float
    step_ms_list: List[float]
    max_mem_mb: float
    approx_cuda_event_count: Optional[int]  # only if profiler enabled


def set_torch_perf_flags():
    # Strong opinion: без TF32 и cudnn.benchmark ты часто меряешь не оптимизацию, а неудачные default'ы.
    torch.backends.cudnn.benchmark = True
    torch.backends.cuda.matmul.allow_tf32 = True
    torch.backends.cudnn.allow_tf32 = True
    try:
        torch.set_float32_matmul_precision("high")
    except Exception:
        pass


def percentile(values: List[float], q: float) -> float:
    if not values:
        return float("nan")
    s = sorted(values)
    idx = int(round((len(s) - 1) * q))
    return s[max(0, min(idx, len(s) - 1))]


def make_synth_batch(n_users: int, batch_size: int, device: torch.device, dtype: torch.dtype, seed: int):
    g = torch.Generator(device="cpu")
    g.manual_seed(seed)

    # Inputs: MNIST-like, padded to 32x32, 1 channel
    x = torch.randn((n_users, batch_size, 1, 32, 32), generator=g, dtype=torch.float32).to(device=device, dtype=dtype)
    # Labels: 0..9
    y = torch.randint(0, 10, (n_users, batch_size), generator=g, dtype=torch.int64).to(device=device)
    return x, y


def run_baseline(
    n_users: int,
    batch_size: int,
    steps: int,
    warmup: int,
    device: torch.device,
    dtype: torch.dtype,
    lr: float,
    use_amp: bool,
    profile: bool,
) -> RunStats:
    models = [LeNet5().to(device=device, dtype=dtype) for _ in range(n_users)]

    # One optimizer over all params (reduces python overhead, keeps compute "unfused")
    params = []
    for m in models:
        params += list(m.parameters())
    opt = torch.optim.SGD(params, lr=lr, momentum=0.0)
    scaler = torch.cuda.amp.GradScaler(enabled=(use_amp and device.type == "cuda"))

    x, y = make_synth_batch(n_users, batch_size, device, dtype, seed=1234)

    def step_once():
        opt.zero_grad(set_to_none=True)
        total_loss = 0.0
        # sequential "users"
        for i in range(n_users):
            with torch.cuda.amp.autocast(enabled=(use_amp and device.type == "cuda")):
                logits = models[i](x[i])
                loss_i = F.cross_entropy(logits, y[i])
                loss_i = loss_i / float(n_users)  # keep total loss scale comparable
            scaler.scale(loss_i).backward()
            total_loss += float(loss_i.detach().cpu())
        scaler.step(opt)
        scaler.update()
        return total_loss

    # Warmup
    for _ in range(warmup):
        step_once()
    if device.type == "cuda":
        torch.cuda.synchronize()
        torch.cuda.reset_peak_memory_stats()

    # Optional profiling (single step snapshot)
    approx_cuda_events = None
    if profile and device.type == "cuda":
        from torch.profiler import profile as tprofile, ProfilerActivity
        with tprofile(activities=[ProfilerActivity.CPU, ProfilerActivity.CUDA], record_shapes=False, profile_memory=False) as prof:
            step_once()
        # Proxy metric: number of CUDA events recorded
        approx_cuda_events = sum(1 for e in prof.events() if getattr(e, "device_type", None) and str(e.device_type) == "DeviceType.CUDA")

    # Timed loop (CUDA events + wall clock)
    step_ms = []
    if device.type == "cuda":
        start = torch.cuda.Event(enable_timing=True)
        end = torch.cuda.Event(enable_timing=True)

        for _ in range(steps):
            start.record()
            step_once()
            end.record()
            torch.cuda.synchronize()
            step_ms.append(start.elapsed_time(end))
    else:
        for _ in range(steps):
            t0 = time.perf_counter()
            step_once()
            t1 = time.perf_counter()
            step_ms.append((t1 - t0) * 1000.0)

    max_mem_mb = 0.0
    if device.type == "cuda":
        max_mem_mb = torch.cuda.max_memory_allocated() / (1024.0 * 1024.0)

    return RunStats(
        avg_step_ms=sum(step_ms) / len(step_ms),
        p50_step_ms=percentile(step_ms, 0.50),
        p90_step_ms=percentile(step_ms, 0.90),
        step_ms_list=step_ms,
        max_mem_mb=max_mem_mb,
        approx_cuda_event_count=approx_cuda_events,
    )


def run_fused_topofuse(
    n_users: int,
    batch_size: int,
    steps: int,
    warmup: int,
    device: torch.device,
    dtype: torch.dtype,
    lr: float,
    use_amp: bool,
    compile_mode: str,
    profile: bool,
) -> RunStats:
    model = BankedLeNet5(n_users=n_users, device=device, dtype=dtype)
    opt = torch.optim.SGD(model.parameters(), lr=lr, momentum=0.0)
    scaler = torch.cuda.amp.GradScaler(enabled=(use_amp and device.type == "cuda"))

    x, y = make_synth_batch(n_users, batch_size, device, dtype, seed=1234)

    def step_once():
        opt.zero_grad(set_to_none=True)
        with torch.cuda.amp.autocast(enabled=(use_amp and device.type == "cuda")):
            logits = model(x)  # (N,B,10)
            loss = F.cross_entropy(logits.view(-1, 10), y.view(-1))
        scaler.scale(loss).backward()
        scaler.step(opt)
        scaler.update()
        return float(loss.detach().cpu())

    # Optional torch.compile (can noticeably reduce python overhead and improve fusion stability)
    if compile_mode != "none":
        # Strong opinion: compile нужен только если у тебя измерения стабильные (warmup и синхронизации уже сделаны).
        # Иначе ты померяешь compile overhead, а не runtime.
        try:
            if compile_mode == "compile":
                model_compiled = torch.compile(model)
                model = model_compiled
            elif compile_mode == "jit":
                model = torch.jit.script(model)
            else:
                raise ValueError("compile_mode must be one of: none|compile|jit")
        except Exception as e:
            print(f"[WARN] compile_mode={compile_mode} failed ({e}); continuing without compile.")
            compile_mode = "none"

    # Warmup
    for _ in range(warmup):
        step_once()
    if device.type == "cuda":
        torch.cuda.synchronize()
        torch.cuda.reset_peak_memory_stats()

    # Optional profiling (single step snapshot)
    approx_cuda_events = None
    if profile and device.type == "cuda":
        from torch.profiler import profile as tprofile, ProfilerActivity
        with tprofile(activities=[ProfilerActivity.CPU, ProfilerActivity.CUDA], record_shapes=False, profile_memory=False) as prof:
            step_once()
        approx_cuda_events = sum(1 for e in prof.events() if getattr(e, "device_type", None) and str(e.device_type) == "DeviceType.CUDA")

    # Timed loop
    step_ms = []
    if device.type == "cuda":
        start = torch.cuda.Event(enable_timing=True)
        end = torch.cuda.Event(enable_timing=True)

        for _ in range(steps):
            start.record()
            step_once()
            end.record()
            torch.cuda.synchronize()
            step_ms.append(start.elapsed_time(end))
    else:
        for _ in range(steps):
            t0 = time.perf_counter()
            step_once()
            t1 = time.perf_counter()
            step_ms.append((t1 - t0) * 1000.0)

    max_mem_mb = 0.0
    if device.type == "cuda":
        max_mem_mb = torch.cuda.max_memory_allocated() / (1024.0 * 1024.0)

    return RunStats(
        avg_step_ms=sum(step_ms) / len(step_ms),
        p50_step_ms=percentile(step_ms, 0.50),
        p90_step_ms=percentile(step_ms, 0.90),
        step_ms_list=step_ms,
        max_mem_mb=max_mem_mb,
        approx_cuda_event_count=approx_cuda_events,
    )


def fmt_ms(x: float) -> str:
    return f"{x:8.3f} ms"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", type=str, default="cuda", help="cuda or cpu")
    parser.add_argument("--dtype", type=str, default="fp32", choices=["fp32", "fp16", "bf16"])
    parser.add_argument("--amp", action="store_true", help="use autocast+GradScaler (cuda only)")
    parser.add_argument("--batch", type=int, default=64)
    parser.add_argument("--users", type=str, default="1,2,4,8,16,32", help="comma separated N values")
    parser.add_argument("--steps", type=int, default=30, help="timed steps")
    parser.add_argument("--warmup", type=int, default=10, help="warmup steps")
    parser.add_argument("--lr", type=float, default=0.01)
    parser.add_argument("--compile", type=str, default="none", choices=["none", "compile", "jit"])
    parser.add_argument("--profile", action="store_true", help="run 1-step torch.profiler snapshot per mode (slower)")
    parser.add_argument("--out_csv", type=str, default="results_lenet5_topofuse.csv")
    parser.add_argument("--mode", type=str, default="both", choices=["both", "baseline", "fused"])

    args = parser.parse_args()

    set_torch_perf_flags()

    # Device
    if args.device == "cuda" and not torch.cuda.is_available():
        print("[WARN] CUDA not available; falling back to CPU.")
        device = torch.device("cpu")
    else:
        device = torch.device(args.device)

    # dtype
    if args.dtype == "fp32":
        dtype = torch.float32
    elif args.dtype == "fp16":
        dtype = torch.float16
    else:
        dtype = torch.bfloat16

    # Parse users list
    n_list = [int(x.strip()) for x in args.users.split(",") if x.strip()]
    n_list = sorted(set(n_list))

    print("=== LeNet-5 TopoFuse-style Benchmark ===")
    print(f"Device: {device} | dtype: {args.dtype} | AMP: {args.amp} | batch: {args.batch}")
    print(f"Steps: {args.steps} | Warmup: {args.warmup} | LR: {args.lr}")
    print(f"Fused compile mode: {args.compile} | Profiler snapshot: {args.profile}")
    print()

    rows = []
    header = [
        "N_users",
        "baseline_avg_ms", "baseline_p50_ms", "baseline_p90_ms",
        "fused_avg_ms", "fused_p50_ms", "fused_p90_ms",
        "speedup_x",
        "baseline_throughput_samples_s",
        "fused_throughput_samples_s",
        "baseline_max_mem_mb",
        "fused_max_mem_mb",
        "baseline_approx_cuda_events",
        "fused_approx_cuda_events",
    ]

    # Table header
    print(f"{'N':>4} | {'Baseline avg':>12} | {'Fused avg':>12} | {'Speedup':>8} | {'Base thrpt':>12} | {'Fused thrpt':>12} | {'Mem base':>9} | {'Mem fused':>9}")
    print("-" * 105)

    for N in n_list:
        base = None
        fused = None

        if args.mode in ("both", "baseline"):
            base = run_baseline(
                n_users=N, batch_size=args.batch, steps=args.steps, warmup=args.warmup,
                device=device, dtype=dtype, lr=args.lr, use_amp=args.amp,
                profile=args.profile
            )

        if args.mode in ("both", "fused"):
            fused = run_fused_topofuse(
                n_users=N, batch_size=args.batch, steps=args.steps, warmup=args.warmup,
                device=device, dtype=dtype, lr=args.lr, use_amp=args.amp,
                compile_mode=args.compile,
                profile=args.profile
            )

        if args.mode == "baseline":
            print(f"{N:4d} | {fmt_ms(base.avg_step_ms):>12} | {'':>12} | {'':>8} | "
                  f"{(N * args.batch) / (base.avg_step_ms / 1000.0):12.0f} | {'':>12} | {base.max_mem_mb:9.0f} | {'':>9}")
            continue

        if args.mode == "fused":
            print(f"{N:4d} | {'':>12} | {fmt_ms(fused.avg_step_ms):>12} | {'':>8} | "
                  f"{'':>12} | {(N * args.batch) / (fused.avg_step_ms / 1000.0):12.0f} | {'':>9} | {fused.max_mem_mb:9.0f}")
            continue

        # both (как было)
        speedup = base.avg_step_ms / fused.avg_step_ms
        base_thrpt = (N * args.batch) / (base.avg_step_ms / 1000.0)
        fused_thrpt = (N * args.batch) / (fused.avg_step_ms / 1000.0)

        print(
            f"{N:4d} | {fmt_ms(base.avg_step_ms):>12} | {fmt_ms(fused.avg_step_ms):>12} | {speedup:8.3f} | "
            f"{base_thrpt:12.0f} | {fused_thrpt:12.0f} | {base.max_mem_mb:9.0f} | {fused.max_mem_mb:9.0f}"
        )

    # Write CSV
    with open(args.out_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)

    print()
    print(f"[OK] CSV saved to: {args.out_csv}")
    print("Suggested plot: X = N_users, Y = avg_ms (baseline vs fused) or speedup_x.")


if __name__ == "__main__":
    main()
