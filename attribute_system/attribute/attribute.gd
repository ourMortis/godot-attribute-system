@abstract class_name Attribute extends Resource
## 属性的抽象类 配合AttributeModifier操作数值

signal on_value_changed(old_value: float, new_value: float)
signal on_modifier_added(modifier: AttributeModifier)
signal on_modifier_removed(modifier: AttributeModifier)

@export var attribute_name: String
@export var formula: AttributeFormula ## 这个属性的计算策略
@export var cur_value: float:
	set(new_value):
		if new_value != cur_value:
			on_value_changed.emit(cur_value, new_value)
			cur_value = new_value

@abstract
func value() -> float ## 获取属性的当前值

@abstract
func add_modifier(modifier: AttributeModifier) -> void

@abstract
func remove_modifier(modifier_uid: String) -> void
