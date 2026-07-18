import io, asyncio
import nns.model_core as nodes
from worker import worker_pebble as wp, worker_tasks as wt
from common.context_cache import contexts

async def get_old_context(logged_in, contexts_root, graph, ctx_name):
	ctx_name = str(ctx_name)
	ctx_ram_key = logged_in.name + ":" + ctx_name
	if ctx_ram_key not in contexts:
		contexts[ctx_ram_key] = nodes.gen_context()
		read = contexts_root.read_rel(f"{ctx_name}.blob")
		if read:
			job_id = wp.submit(
				wt.load_graph_task,
				dict(graph=graph, load_from=io.BytesIO(read), context=contexts[ctx_ram_key])
			)
			await wp.wait_done(job_id)
	return contexts[ctx_ram_key]

