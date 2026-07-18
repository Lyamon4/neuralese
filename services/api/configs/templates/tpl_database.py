from rocksdict import Rdict, Options

class Database:
	def __init__(self, path: str):
		opts = Options()
		opts.create_if_missing(True)
		self.db = Rdict(path, opts)

	def get(self, key: str):
		val = self.db.get(key)
		return val if val is not None else None

	def put(self, key: str, value: bytes):
		self.db[key] = value

	def delete(self, key: str):
		try:
			del self.db[key]
		except KeyError:
			pass

	def close(self):
		self.db.close()
