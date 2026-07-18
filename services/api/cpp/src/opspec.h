#pragma once
#include <vector>

enum class OpType {
	Dense,
	Flatten
};

struct OpSpec {
	OpType type;
	std::vector<int> inputs;
	std::vector<int> outputs;

	// resolved at BUILD time
	int in_features = -1;
	int out_features = -1;
	int activation = 0; // 0=none,1=relu,2=sigmoid,3=tanh
};
