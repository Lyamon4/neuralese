#include <pybind11/pybind11.h>
#include <pybind11/stl.h>
#include <torch/extension.h>

#include "ops.h"
#include "executor.h"

namespace py = pybind11;

PYBIND11_MODULE(neuralese_ops, m) {

	py::enum_<ActivationType>(m, "ActivationType")
		.value("NONE", ActivationType::None)
		.value("ReLU", ActivationType::ReLU)
		.value("Sigmoid", ActivationType::Sigmoid)
		.value("Tanh", ActivationType::Tanh)
		.value("GELU", ActivationType::GELU);

	py::enum_<MergeType>(m, "MergeType")
		.value("Add", MergeType::Add)
		.value("Mean", MergeType::Mean);

	py::class_<Op, std::shared_ptr<Op>>(m, "Op");

	py::class_<DenseOp, Op, std::shared_ptr<DenseOp>>(m, "DenseOp")
		.def(py::init<int,int,int,int,ActivationType,bool,c10::Device>(),
			py::arg("input"), py::arg("output"),
			py::arg("in_features"), py::arg("out_features"),
			py::arg("activation"), py::arg("bias"),
			py::arg("device"));

	py::class_<Conv2DOp, Op, std::shared_ptr<Conv2DOp>>(m, "Conv2DOp")
		.def(py::init<int,int,int,int,int,int,int,ActivationType,bool,c10::Device>(),
			py::arg("input"), py::arg("output"),
			py::arg("in_channels"), py::arg("out_channels"),
			py::arg("kernel"), py::arg("stride"), py::arg("padding"),
			py::arg("activation"), py::arg("bias"),
			py::arg("device"));

	py::class_<MaxPool2DOp, Op, std::shared_ptr<MaxPool2DOp>>(m, "MaxPool2DOp")
		.def(py::init<int,int,int>(),
			py::arg("input"), py::arg("output"), py::arg("k"));

	py::class_<FlattenOp, Op, std::shared_ptr<FlattenOp>>(m, "FlattenOp")
		.def(py::init<int,int>(), py::arg("input"), py::arg("output"));

	py::class_<DropoutOp, Op, std::shared_ptr<DropoutOp>>(m, "DropoutOp")
		.def(py::init<int,int,double,bool,c10::Device>(),
			py::arg("input"), py::arg("output"),
			py::arg("p"), py::arg("training"), py::arg("device"));

	py::class_<ConcatOp, Op, std::shared_ptr<ConcatOp>>(m, "ConcatOp")
		.def(py::init<std::vector<int>,int,int>(),
			py::arg("inputs_ordered"), py::arg("output"), py::arg("dim"));

	py::class_<MergeOp, Op, std::shared_ptr<MergeOp>>(m, "MergeOp")
		.def(py::init<std::vector<int>,int,MergeType>(),
			py::arg("inputs_ordered"), py::arg("output"), py::arg("mode"));

	py::class_<Executor>(m, "Executor")
		.def(py::init<std::vector<std::shared_ptr<Op>>, c10::Device>(),
			py::arg("ops"), py::arg("device"))
		.def("set_tensor", &Executor::set_tensor, py::arg("id"), py::arg("tensor"))
		.def("get_tensor", &Executor::get_tensor, py::arg("id"))
		.def("run", &Executor::run)
		.def("run_n", &Executor::run_n, py::arg("n"))
		.def("set_training", &Executor::set_training, py::arg("is_training"))
		.def("capture", &Executor::capture, py::arg("warmup") = 3)
		.def("replay", &Executor::replay)
		.def("has_graph", &Executor::has_graph);
}
