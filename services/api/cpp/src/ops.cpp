#include "ops.h"

// Dense
DenseOp::DenseOp(int in,int out,int fin,int fout,ActivationType a,bool bias,c10::Device d)
	: in_id(in), out_id(out), act(a)
{
	linear = torch::nn::Linear(torch::nn::LinearOptions(fin, fout).bias(bias));
	linear->to(d);
}

at::Tensor DenseOp::forward_unary(const at::Tensor& xin) {
	auto x = xin;
	if (x.dim() > 2) x = x.contiguous().view({x.size(0), -1});
	auto y = linear->forward(x);
	return apply_activation(y, act);
}

void DenseOp::run(TensorVec& t) {
	t[out_id] = forward_unary(t[in_id]);
}

// Conv2D
Conv2DOp::Conv2DOp(int in,int out,int cin,int cout,int k,int s,int p,ActivationType a,bool bias,c10::Device d)
	: in_id(in), out_id(out), act(a)
{
	conv = torch::nn::Conv2d(
		torch::nn::Conv2dOptions(cin, cout, k).stride(s).padding(p).bias(bias)
	);
	conv->to(d);
}

at::Tensor Conv2DOp::forward_unary(const at::Tensor& xin) {
	auto x = xin;
	if (x.dim() == 3) x = x.unsqueeze(1); // [N,H,W] -> [N,1,H,W]
	auto y = conv->forward(x);
	return apply_activation(y, act);
}

void Conv2DOp::run(TensorVec& t) {
	t[out_id] = forward_unary(t[in_id]);
}

// Pool
MaxPool2DOp::MaxPool2DOp(int in,int out,int k_) : in_id(in), out_id(out), k(k_) {}

at::Tensor MaxPool2DOp::forward_unary(const at::Tensor& x) {
	return torch::max_pool2d(x, {k,k}, {k,k});
}

void MaxPool2DOp::run(TensorVec& t) {
	t[out_id] = forward_unary(t[in_id]);
}

// Flatten
FlattenOp::FlattenOp(int in,int out) : in_id(in), out_id(out) {}

at::Tensor FlattenOp::forward_unary(const at::Tensor& x) {
	return x.flatten(1);
}

void FlattenOp::run(TensorVec& t) {
	t[out_id] = forward_unary(t[in_id]);
}

// Dropout
DropoutOp::DropoutOp(int in,int out,double p,bool train,c10::Device d)
	: in_id(in), out_id(out)
{
	drop = torch::nn::Dropout(torch::nn::DropoutOptions(p));
	drop->to(d);
	drop->train(train);
}

at::Tensor DropoutOp::forward_unary(const at::Tensor& x) {
	return drop->forward(x);
}

void DropoutOp::run(TensorVec& t) {
	t[out_id] = forward_unary(t[in_id]);
}

// Concat
ConcatOp::ConcatOp(std::vector<int> ids,int out,int dim_) : in_ids(std::move(ids)), out_id(out), dim(dim_) {}

void ConcatOp::run(TensorVec& t) {
	std::vector<at::Tensor> xs;
	xs.reserve(in_ids.size());
	for (int id : in_ids) xs.push_back(t[id]);
	t[out_id] = torch::cat(xs, dim);
}

// Merge
MergeOp::MergeOp(std::vector<int> ids,int out,MergeType m) : in_ids(std::move(ids)), out_id(out), mode(m) {}

void MergeOp::run(TensorVec& t) {
	auto y = t[in_ids[0]];
	for (size_t i=1;i<in_ids.size();++i) y = y + t[in_ids[i]];
	if (mode == MergeType::Mean) y = y / (double)in_ids.size();
	t[out_id] = y;
}
