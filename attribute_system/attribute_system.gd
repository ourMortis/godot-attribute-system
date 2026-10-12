class_name AttributeSystem extends Node
## 这是一个通用,组件化的属性系统 支持多种属性热拔插,采用不同计算策略,追踪修改情况
## 
## 属性当前值 = 基础值 + 修改器
## Attribute          仅负责存储与该属性相关的数值
## AttributeModifier  辅助存储数值的修改情况
## AttributeSystem    负责对外接口和统一调度管理
## 
## 注意事项:
## 这套逻辑适合 "最大生命值" "防御力" "攻击力" 等会被装备和buff影响的属性
## 特点是 随着装备和buff的装载和卸载 属性值随之变化; 也就是: Modifier 有增有删
## 如果是 "当前生命值" 这种不需要以上功能的属性 直接调用get_base_value和set_base_value即可
## "当前生命值" 应该采用增量更新 并且相关的 Modifier 应该永久生效 这套系统中将导致溢出
##
## 属性的当前值缓存不会在增删修改器后自动刷新 需要调用get_value或update_value
##

signal on_attribute_added(attribute: Attribute)
signal on_attribute_removed(attribute: Attribute)

## 通过属性名称 快速索引属性
@export var attributes: Dictionary[String, Attribute] = {}
## 通过修改器uid 快速索引修改器所在属性
var target_of_modifiers: Dictionary[String, Attribute] = {}

func add_attribute(attribute_name: String, base_value: float) -> void:
	var attribute: Attribute = Attribute.new()
	attribute.attribute_name = attribute_name
	attribute.base_value = base_value
	attributes[attribute.attribute_name] = attribute
	on_attribute_added.emit(attribute)

func remove_attribute(attribute_name: String) -> void:
	var tmp: Attribute = attributes[attribute_name]
	attributes.erase(attribute_name)
	on_attribute_removed.emit(tmp)

## get之前会自动刷新当前值
func get_value(attribute_name: String) -> float:
	return attributes[attribute_name].update_and_get_value()

func update_value(attribute_name: String) -> void:
	attributes[attribute_name].update_value()

func get_base_value(attribute_name: String) -> float:
	return attributes[attribute_name].base_value

func set_base_value(attribute_name: String, value: float) -> void:
	attributes[attribute_name].base_value = value

func add_modifier(modifier_uid: String, type: AttributeModifier.ModifierType, tag: int, value: float, target_atrribute_name: String) -> void:
	var modifier: AttributeModifier = AttributeModifier.new()
	modifier.modifier_uid = modifier_uid
	modifier.type = type
	modifier.tag = tag
	modifier.value = value

	var attribute: Attribute = attributes[target_atrribute_name]
	target_of_modifiers[modifier_uid] = attribute
	attribute.add_modifier(modifier)

func remove_modifier(modifier_uid: String) -> void:
	target_of_modifiers[modifier_uid].remove_modifier(modifier_uid)
	target_of_modifiers.erase(modifier_uid)
