#pragma once
#include <vector>
#include <memory>
#include <optional>

#include <torch/torch.h>
#include <ATen/cuda/CUDAGraph.h>
#include <ATen/cuda/CUDAContext.h>

#include "ops.h"

class FusedUnaryChainOp final : public Op {
	std::vector<std::shared_ptr<Op>> chain;
	int in_id = -1;
	int out_id = -1;

public:
	explicit FusedUnaryChainOp(std::vector<std::shared_ptr<Op>> ops_chain);

	void run(TensorVec&) override;

	void input_ids(std::vector<int>& out) const override { out.push_back(in_id); }
	void output_ids(std::vector<int>& out) const override { out.push_back(out_id); }

	void set_training(bool t) override;
	void to(const c10::Device& d) override;
};

class Executor {
public:
	explicit Executor(std::vector<std::shared_ptr<Op>> ops_, c10::Device device);

	void set_tensor(int id, const at::Tensor& t);
	at::Tensor get_tensor(int id) const;

	void run();
	void run_n(int64_t n);

	void set_training(bool is_training);

	void capture(int warmup = 3);
	void replay();
	bool has_graph() const { return graph_ready; }

private:
	// original ops (ownership)
	std::vector<std::shared_ptr<Op>> ops;

	// execution plan (can contain fused blocks)
	std::vector<std::shared_ptr<Op>> exec_ops;

	TensorVec tensors;
	c10::Device device;

	bool graph_ready = false;
	at::cuda::CUDAGraph graph;

	// keep capture stream (non-default)
	std::optional<at::cuda::CUDAStream> graph_stream;

	void build_exec_plan();
	void init_tensor_storage();
};
