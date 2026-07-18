// ops.h
#pragma once
#include <torch/extension.h>
#include <memory>

struct Op {
	virtual ~Op() = default;      // ОБЯЗАТЕЛЬНО
	virtual void run(TensorTable&) = 0;
};
