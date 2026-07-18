extends Control
class_name Wrapper

var wrapping_target: BlockComponent

func _enter_tree() -> void:
	self.mouse_filter = Control.MOUSE_FILTER_PASS
