# Axon Retrieval Manual Tests

Use these scenarios after launching the clean backend.

1. Greeting
   - Input: `yo`
   - Expected: compact prompt only; no `get_current_graph_summary`, no `full_node_docs`, no build tool.

2. Graph read
   - Input: `what is in my graph?`
   - Expected: calls `get_current_graph_summary`; no build tool.

3. Advice question with action verb
   - Input: `should we add dropout?`
   - Expected: no build. It may inspect graph and answer advice.

4. Direct modification
   - Input: `add dropout after the first dense layer`
   - Expected: inspect graph if needed, optionally retrieve `dropout,dense_layer` docs, then call `build_graph`.

5. Node documentation question
   - Input: `what ports does conv2d use?`
   - Expected: calls `full_node_docs("conv2d_layer")`; no build.

6. Unknown node
   - Input: `add batch norm`
   - Expected: does not invent a node; says it is unavailable or suggests available alternatives.

7. Specialized builder
   - Input: `build a two-layer CNN for MNIST`
   - Expected: if canvas is empty, may call `build_graph_digit_2_conv`; if not empty, use `build_graph` or explain.

Watch backend logs for:
- compact prompt character length
- exposed tool names
- graph summary/full scene/node docs loaded flags
- graph build flag
