try:
	from .fs_core import Database
	from .fs_node import Node
except Exception as e:
	from fs_core import Database
	from fs_node import Node

