extends Node2D


@onready var attribute_system: AttributeSystem = $AttributeSystem
var uid: int = 0:
	get():
		uid += 1
		return uid

func _ready() -> void:
	attribute_system.attributes["health"].on_attribute_base_value_changed.connect(_on_health_changed)
	attribute_system.attributes["max_health"].on_attribute_value_changed.connect(_on_max_health_changed)
	attribute_system.attributes["attack"].on_attribute_value_changed.connect(_on_attack_changed)


func _on_health_changed(old_value: float, new_value: float) -> void:
	print("    health: %5f -> %5f" % [old_value, new_value])

func _on_max_health_changed(old_value: float, new_value: float) -> void:
	print("max_health: %5f -> %5f" % [old_value, new_value])

func _on_attack_changed(old_value: float, new_value: float) -> void:
	print("    attack: %5f -> %5f" % [old_value, new_value])

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("1"):
		f1()
	if event.is_action_pressed("2"):
		f2()
	if event.is_action_pressed("3"):
		f3()
		
		
func f1() -> void:
	var base = attribute_system.get_base_value("health")
	attribute_system.set_base_value("health", base - 2)
func f2() -> void:
	attribute_system.add_modifier(str(uid), AttributeModifier.ModifierType.ADD, 0, -2, "max_health")
	attribute_system.attributes["max_health"].update_value()
func f3() -> void:
	attribute_system.add_modifier(str(uid), AttributeModifier.ModifierType.MUL, 0, 1.1, "attack")
	attribute_system.attributes["attack"].update_value()
