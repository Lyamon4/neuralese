import time

import torch
print(torch.version.cuda)
print(torch.__version__)
quit()

import neuralese_ops as ops

device = torch.device("cuda:0")

op_conv = ops.Conv2DOp(
	input=0, output=1,
	in_channels=1, out_channels=8,
	kernel=3, stride=1, padding=1,
	activation=ops.ActivationType.ReLU,
	bias=True,
	device=device
)

op_pool  = ops.MaxPool2DOp(input=1, output=2, k=2)
op_flat  = ops.FlattenOp(input=2, output=3)
op_dense = ops.DenseOp(input=3, output=4, in_features=8*14*14, out_features=10,
	activation=ops.ActivationType.NONE, bias=True, device=device)

ex = ops.Executor([op_conv, op_pool, op_flat, op_dense], device)

# ВАЖНО: input должен быть CUDA сразу
x = torch.randn(32, 28, 28, device=device)

ex.set_training(True)
ex.set_tensor(0, x)

# 1) Capture один раз
ex.capture(warmup=5)

t = time.perf_counter()
# 2) Дальше гоняем replay (или run_n)
for i in range(50000//32):
	ex.run()          # <- это должно быть уже "по-взрослому"
# или:
print(time.perf_counter() - t)
# for _ in range(50000): ex.replay()

y = ex.get_tensor(4)
print(y.device, y.shape)
