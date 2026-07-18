extends Control

signal ip_entered(ip: String)

func _ready() -> void:
	$LineEdit.text = glob.get_var("lan_ip", "")

func _on_button_pressed() -> void:
	if $LineEdit.text.is_valid_ip_address():
		var full = "http://" + $LineEdit.text + ":8000/health"
		var health = await web.HEALTH(full)
		
		if health:
			ip_entered.emit($LineEdit.text)
			queue_free()
