class_name InstantAttribute extends Attribute
## 一次性的修改器不需要存储 适合"当前生命值"这种属性

func value() -> float:
	return cur_value

func add_modifier(modifier: AttributeModifier) -> void:
	cur_value = formula.calculate(cur_value, [modifier])

func remove_modifier(modifier_uid: String) -> void:
	return
