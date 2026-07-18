#pragma once
#include <torch/torch.h>
#include <vector>
#include <memory>

using TensorVec = std::vector<at::Tensor>;

enum class ActivationType {
	None,
	ReLU,
	Sigmoid,
	Tanh,
	GELU
};

inline at::Tensor apply_activation(const at::Tensor& x, ActivationType a) {
	switch (a) {
		case ActivationType::ReLU:    return torch::relu(x);
		case ActivationType::Sigmoid: return torch::sigmoid(x);
		case ActivationType::Tanh:    return torch::tanh(x);
		case ActivationType::GELU:    return torch::gelu(x);
		default:                      return x;
	}
}

enum class MergeType { Add, Mean };

class Op {
public:
	virtual ~Op() = default;

	// runtime
	virtual void run(TensorVec&) = 0;

	// build-time introspection (для планировщика/fusion)
	virtual void input_ids(std::vector<int>& out) const = 0;
	virtual void output_ids(std::vector<int>& out) const = 0;

	// optional controls
	virtual void set_training(bool) {}
	virtual void to(const c10::Device&) {}

	// unary fast-path (1 input -> 1 output)
	virtual bool is_unary() const { return false; }
	virtual int unary_in() const { return -1; }
	virtual int unary_out() const { return -1; }
	virtual at::Tensor forward_unary(const at::Tensor& x) { return x; }
};

// -------- Dense --------
class DenseOp final : public Op {
	int in_id, out_id;
	ActivationType act;
	torch::nn::Linear linear{nullptr};
public:
	DenseOp(int in,int out,int fin,int fout,ActivationType a,bool bias,c10::Device d);

	void run(TensorVec&) override;

	void input_ids(std::vector<int>& out) const override { out.push_back(in_id); }
	void output_ids(std::vector<int>& out) const override { out.push_back(out_id); }

	bool is_unary() const override { return true; }
	int unary_in() const override { return in_id; }
	int unary_out() const override { return out_id; }
	at::Tensor forward_unary(const at::Tensor& x) override;

	void to(const c10::Device& d) override { linear->to(d); }
};

// -------- Conv2D --------
class Conv2DOp final : public Op {
	int in_id, out_id;
	ActivationType act;
	torch::nn::Conv2d conv{nullptr};
public:
	Conv2DOp(int in,int out,int cin,int cout,int k,int s,int p,ActivationType a,bool bias,c10::Device d);

	void run(TensorVec&) override;

	void input_ids(std::vector<int>& out) const override { out.push_back(in_id); }
	void output_ids(std::vector<int>& out) const override { out.push_back(out_id); }

	bool is_unary() const override { return true; }
	int unary_in() const override { return in_id; }
	int unary_out() const override { return out_id; }
	at::Tensor forward_unary(const at::Tensor& x) override;

	void to(const c10::Device& d) override { conv->to(d); }
};

// -------- MaxPool --------
class MaxPool2DOp final : public Op {
	int in_id, out_id, k;
public:
	MaxPool2DOp(int in,int out,int k_);

	void run(TensorVec&) override;

	void input_ids(std::vector<int>& out) const override { out.push_back(in_id); }
	void output_ids(std::vector<int>& out) const override { out.push_back(out_id); }

	bool is_unary() const override { return true; }
	int unary_in() const override { return in_id; }
	int unary_out() const override { return out_id; }
	at::Tensor forward_unary(const at::Tensor& x) override;
};

// -------- Flatten --------
class FlattenOp final : public Op {
	int in_id, out_id;
public:
	FlattenOp(int in,int out);

	void run(TensorVec&) override;

	void input_ids(std::vector<int>& out) const override { out.push_back(in_id); }
	void output_ids(std::vector<int>& out) const override { out.push_back(out_id); }

	bool is_unary() const override { return true; }
	int unary_in() const override { return in_id; }
	int unary_out() const override { return out_id; }
	at::Tensor forward_unary(const at::Tensor& x) override;
};

// -------- Dropout --------
class DropoutOp final : public Op {
	int in_id, out_id;
	torch::nn::Dropout drop{nullptr};
public:
	DropoutOp(int in,int out,double p,bool train,c10::Device d);

	void set_training(bool t) override { drop->train(t); }

	void run(TensorVec&) override;

	void input_ids(std::vector<int>& out) const override { out.push_back(in_id); }
	void output_ids(std::vector<int>& out) const override { out.push_back(out_id); }

	bool is_unary() const override { return true; }
	int unary_in() const override { return in_id; }
	int unary_out() const override { return out_id; }
	at::Tensor forward_unary(const at::Tensor& x) override;

	void to(const c10::Device& d) override { drop->to(d); }
};

// -------- Concat --------
class ConcatOp final : public Op {
	std::vector<int> in_ids;
	int out_id, dim;
public:
	ConcatOp(std::vector<int> ids,int out,int dim_);

	void run(TensorVec&) override;

	void input_ids(std::vector<int>& out) const override { out.insert(out.end(), in_ids.begin(), in_ids.end()); }
	void output_ids(std::vector<int>& out) const override { out.push_back(out_id); }
};

// -------- Merge --------
class MergeOp final : public Op {
	std::vector<int> in_ids;
	int out_id;
	MergeType mode;
public:
	MergeOp(std::vector<int> ids,int out,MergeType m);

	void run(TensorVec&) override;

	void input_ids(std::vector<int>& out) const override { out.insert(out.end(), in_ids.begin(), in_ids.end()); }
	void output_ids(std::vector<int>& out) const override { out.push_back(out_id); }
};
