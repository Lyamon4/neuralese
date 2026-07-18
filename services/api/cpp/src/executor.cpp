#include "executor.h"

#include <c10/util/Exception.h>
#include <c10/cuda/CUDAGuard.h>
#include <ATen/cuda/CUDAGraph.h>
#include <ATen/cuda/CUDAContext.h>

// ---------------- FusedUnaryChainOp ----------------

FusedUnaryChainOp::FusedUnaryChainOp(std::vector<std::shared_ptr<Op>> ops_chain)
	: chain(std::move(ops_chain))
{
	TORCH_CHECK(!chain.empty(), "FusedUnaryChainOp: empty chain");
	TORCH_CHECK(chain.front()->is_unary() && chain.back()->is_unary(),
		"FusedUnaryChainOp: chain must be unary");

	in_id  = chain.front()->unary_in();
	out_id = chain.back()->unary_out();

	for (size_t i = 0; i + 1 < chain.size(); ++i) {
		TORCH_CHECK(chain[i]->unary_out() == chain[i + 1]->unary_in(),
			"FusedUnaryChainOp: broken chain");
	}
}

void FusedUnaryChainOp::run(TensorVec& t) {
	at::Tensor x = t[in_id];
	for (auto& op : chain) {
		x = op->forward_unary(x);
	}
	t[out_id] = x;
}

void FusedUnaryChainOp::set_training(bool tr) {
	for (auto& op : chain) op->set_training(tr);
}

void FusedUnaryChainOp::to(const c10::Device& d) {
	for (auto& op : chain) op->to(d);
}

// ---------------- Executor ----------------

Executor::Executor(std::vector<std::shared_ptr<Op>> ops_, c10::Device device_)
	: ops(std::move(ops_)), device(device_)
{
	for (auto& op : ops) op->to(device);
	init_tensor_storage();
	build_exec_plan();
}

void Executor::capture(int warmup) {
	TORCH_CHECK(device.is_cuda(), "capture(): CUDA only");
	TORCH_CHECK(!graph_ready, "capture(): already captured");

	c10::cuda::CUDAGuard guard(device);

	// warmup on default stream
	for (int i = 0; i < warmup; ++i) run();
	at::cuda::synchronize();  // <-- ОБЯЗАТЕЛЬНО СКОБКИ

	// create NON-default stream
	graph_stream.emplace(
		at::cuda::getStreamFromPool(false, device.index())
	);

	at::cuda::CUDAStreamGuard stream_guard(*graph_stream);

	graph.capture_begin();
	run();
	graph.capture_end();

	graph_ready = true;
}

void Executor::replay() {
	TORCH_CHECK(graph_ready, "graph not captured");
	TORCH_CHECK(graph_stream.has_value(), "graph stream missing");

	at::cuda::CUDAStreamGuard stream_guard(*graph_stream);
	graph.replay();
}
