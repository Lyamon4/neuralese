class_name Queue

var _data:Dictionary = {}
var _head:int = 0
var _tail:int = 0

func duplicate() -> Queue:
	var q = Queue.new()
	q._data = _data; q._head = _head; q._tail = _tail
	return q

func push(item):
	_data[_tail] = item
	_tail += 1

func append(item):
	_data[_tail] = item
	_tail += 1

func clear():
	_head = 0; _tail = 0; _data.clear()

func pop_back() -> Variant:
	if _head >= _tail:
		_head = 0; _tail = 0
		return null
	var item = _data[_head]
	_data.erase(_head)
	_head += 1
	return item

func access() -> Variant:
	if _head >= _tail:
		return null
	return _data[_head]

func pop() -> Variant:
	if _head >= _tail:
		_head = 0; _tail = 0
		return null
	var item = _data[_head]
	_data.erase(_head)
	_head += 1
	return item

func empty() -> bool:
	return _head >= _tail

func size() -> int:
	return _tail - _head
