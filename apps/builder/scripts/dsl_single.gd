extends Node
class_name LessonRouter

static var active_lesson: LessonCode = null

static func register_lesson(lesson: LessonCode) -> void:
	active_lesson = lesson


static func unregister_lesson(lesson: LessonCode) -> void:
	if active_lesson == lesson:
		active_lesson = null

# Called by graph / editor events
static func notify_graph_changed() -> void:
	if active_lesson:
		active_lesson.on_graph_changed()
