class_name Attribute extends Resource
## 一个存储了 值 + 修改器 和 基本增删改查操作 的数据类

signal on_attribute_value_changed(old_value: float, new_value: float)
signal on_attribute_base_value_changed(old_value: float, new_value: float)
signal on_modifier_added(modifier: AttributeModifier)
signal on_modifier_removed(modifier: AttributeModifier)

@export var attribute_name: String
@export var base_value: float:
	set(new_value):
		if new_value != base_value:
			on_attribute_base_value_changed.emit(base_value, new_value)
			base_value = new_value
			is_dirty = true

## 缓存的当前值 采用is_dirty判断是否应该刷新 需要手动调用 update
var cur_value: float:
	set(new_value):
		if new_value != cur_value:
			on_attribute_value_changed.emit(cur_value, new_value)
			cur_value = new_value
var is_dirty: bool = true

## 挂载在这个属性上的所有修改器
var modifiers: Dictionary[String, AttributeModifier] = {}

## 这个属性的计算策略
@export var formula: AttributeFormula

func _init() -> void:
	cur_value = base_value

func update_and_get_value() -> float:
	if is_dirty and formula:
		is_dirty = false
		cur_value = formula.calculate(base_value, modifiers.values())
	return cur_value

func update_value() -> void:
	if is_dirty and formula:
		is_dirty = false
		cur_value = formula.calculate(base_value, modifiers.values())

func add_modifier(modifier: AttributeModifier) -> void:
	modifiers[modifier.modifier_uid] = modifier
	is_dirty = true
	on_modifier_added.emit(modifier)

func remove_modifier(modifier_uid: String) -> void:
	var modifier: AttributeModifier = modifiers[modifier_uid]
	modifiers.erase(modifier_uid)
	is_dirty = true
	on_modifier_removed.emit(modifier)
