class_name BuffableAttribute extends Attribute
## 会被 buff效果 装备效果 影响的属性
## 由一个 基础值 + f(其他值...) 计算得出
## 特点是: 数值的修改会随着buff和装备的卸载而卸载
## 不适用于当前生命这种 修改永久生效 的属性

signal on_attribute_base_value_changed(old_value: float, new_value: float)

@export var base_value: float: ## 对基础值的操作不需要调用接口
	set(new_value):
		if new_value != base_value:
			on_attribute_base_value_changed.emit(base_value, new_value)
			base_value = new_value
			is_dirty = true
			cur_value = base_value ## 为了"初始化"时能同步base_value和cur_value 出此下策

var is_dirty: bool = true ## 这是一个懒更新的属性 增删修改器后不会立刻更新当前值

## 挂载在这个属性上的所有修改器
var modifiers: Dictionary[String, AttributeModifier] = {}

## 检查器中修改 base_value 的时序在 init 调用之后 所以这段逻辑不会同步cur_value
##func _init() -> void:
## 	cur_value = base_value

func value() -> float: ## 更新并获取当前值
	if is_dirty and formula:
		is_dirty = false
		cur_value = formula.calculate(base_value, modifiers.values())
	return cur_value

func add_modifier(modifier: AttributeModifier) -> void:
	modifiers[modifier.modifier_uid] = modifier
	is_dirty = true
	on_modifier_added.emit(modifier)

func remove_modifier(modifier_uid: String) -> void:
	var modifier: AttributeModifier = modifiers[modifier_uid]
	modifiers.erase(modifier_uid)
	is_dirty = true
	on_modifier_removed.emit(modifier)

func change_modifier(modifier_uid: String, new_value: float) -> void:
	modifiers[modifier_uid].value = new_value
	is_dirty = true

func update_value() -> void: ## 更新当前值
	if is_dirty and formula:
		is_dirty = false
		cur_value = formula.calculate(base_value, modifiers.values())
