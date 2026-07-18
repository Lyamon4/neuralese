from __future__ import annotations

import unittest

from axon.graph_summary import summarize_graph


class GraphSummaryTests(unittest.TestCase):
    def test_branch_join_concat_is_not_dropped(self) -> None:
        scene = {
            "nodes": {
                "input_1d_0": {
                    "type": "input_1d",
                    "config": {"input_features": [{"text": "0"}]},
                },
                "activation_relu": {
                    "type": "activation",
                    "config": {"activ": "relu"},
                },
                "dense_0": {
                    "type": "dense_layer",
                    "config": {"neuron_count": 32},
                },
                "dense_1": {
                    "type": "dense_layer",
                    "config": {"neuron_count": 16},
                },
                "activation_tanh": {
                    "type": "activation",
                    "config": {"activ": "tanh"},
                },
                "activation_sigmoid": {
                    "type": "activation",
                    "config": {"activ": "sigmoid"},
                },
                "branch_a": {
                    "type": "dense_layer",
                    "config": {"neuron_count": 1},
                },
                "branch_b": {
                    "type": "dense_layer",
                    "config": {"neuron_count": 1},
                },
                "concat_0": {"type": "concat", "config": {}},
                "labels": {
                    "type": "out_labels",
                    "config": {"label_names": ["steer", "throttle"], "title": "control"},
                },
            },
            "edges": [
                {"from": {"tag": "input_1d_0", "port": 0}, "to": {"tag": "dense_0", "port": 1}},
                {"from": {"tag": "activation_relu", "port": 0}, "to": {"tag": "dense_0", "port": 0}},
                {"from": {"tag": "dense_0", "port": 0}, "to": {"tag": "dense_1", "port": 1}},
                {"from": {"tag": "dense_1", "port": 0}, "to": {"tag": "branch_a", "port": 1}},
                {"from": {"tag": "dense_1", "port": 0}, "to": {"tag": "branch_b", "port": 1}},
                {"from": {"tag": "activation_tanh", "port": 0}, "to": {"tag": "branch_a", "port": 0}},
                {"from": {"tag": "activation_sigmoid", "port": 0}, "to": {"tag": "branch_b", "port": 0}},
                {"from": {"tag": "branch_a", "port": 0}, "to": {"tag": "concat_0", "port": 6}},
                {"from": {"tag": "branch_b", "port": 0}, "to": {"tag": "concat_0", "port": 7}},
                {"from": {"tag": "concat_0", "port": 0}, "to": {"tag": "labels", "port": 1}},
            ],
        }

        summary = summarize_graph(scene)

        self.assertIn("split[", summary)
        self.assertIn("dense(neurons=1, activation=tanh)", summary)
        self.assertIn("dense(neurons=1, activation=sigmoid)", summary)
        self.assertIn("-> concat -> out_labels", summary)

    def test_disjoint_input_graphs_are_both_summarized(self) -> None:
        scene = {
            "nodes": {
                "input_1d_a": {"type": "input_1d", "config": {"input_features": [{}]}},
                "dense_a": {"type": "dense_layer", "config": {"neuron_count": 4}},
                "input_1d_b": {"type": "input_1d", "config": {"input_features": [{}, {}]}},
                "dense_b": {"type": "dense_layer", "config": {"neuron_count": 8}},
            },
            "edges": [
                {"from": {"tag": "input_1d_a", "port": 0}, "to": {"tag": "dense_a", "port": 1}},
                {"from": {"tag": "input_1d_b", "port": 0}, "to": {"tag": "dense_b", "port": 1}},
            ],
        }

        summary = summarize_graph(scene)

        self.assertIn("input_1d(features=1) -> dense(neurons=4)", summary)
        self.assertIn("input_1d(features=2) -> dense(neurons=8)", summary)
        self.assertIn(" | ", summary)


if __name__ == "__main__":
    unittest.main()
