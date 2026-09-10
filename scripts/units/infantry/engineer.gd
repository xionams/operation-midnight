extends UnitBase
class_name Engineer

## Unarmed. Its entire value is walking into an enemy structure and
## taking it, so it must be escorted - alone it dies to anything.

func _ready() -> void:
	super._ready()
	var capture := CaptureAbility.new()
	capture.name = "CaptureAbility"
	add_child(capture)
