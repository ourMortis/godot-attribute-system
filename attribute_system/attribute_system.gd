class_name AttributeSystem extends Node
## 这是一个通用,组件化的属性系统 支持多种属性热拔插,采用不同计算策略,追踪修改情况
## 
## Attribute          仅负责存储与该属性相关的数值
## AttributeModifier  辅助描述数值的修改情况
## AttributeSystem    负责对外接口和统一调度管理
## 
## 注意事项:
## 如果是 "最大生命值" "防御力" "攻击力" 等会被装备和buff影响的属性
## 特点是 随着装备和buff的装载和卸载 属性值随之变化; 也就是: Modifier 有增有删
## 请使用 BuffableAttribute
##
## 如果是 "当前生命值", 这种属性相关的 Modifier 应该永久生效, 如果存储在这些修改器 将导致溢出
## 请使用 InstantAttribute
## 

signal on_attribute_added(attribute: Attribute)
signal on_attribute_removed(attribute: Attribute)

## 通过属性名称 快速索引属性
@export var attributes: Dictionary[String, Attribute] = {}
## 通过修改器uid 快速索引修改器所在属性
var target_of_modifiers: Dictionary[String, Attribute] = {}

func add_attribute(attribute: Attribute) -> void:
	attributes[attribute.attribute_name] = attribute
	on_attribute_added.emit(attribute)

func remove_attribute(attribute_name: String) -> void:
	var tmp: Attribute = attributes[attribute_name]
	attributes.erase(attribute_name)
	on_attribute_removed.emit(tmp)

## get之前会自动刷新当前值
func get_value(attribute_name: String) -> float:
	return attributes[attribute_name].value()

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
	attribute.add_modifier(modifier)
	if attribute is BuffableAttribute:
		target_of_modifiers[modifier_uid] = attribute

func remove_modifier(modifier_uid: String) -> void:
	target_of_modifiers[modifier_uid].remove_modifier(modifier_uid)
	target_of_modifiers.erase(modifier_uid)

func change_modifier_value(modifier_uid: String, value: float) -> void:
	var attribute: Attribute = target_of_modifiers[modifier_uid]
	if attribute is BuffableAttribute:
		attribute.change_modifier(modifier_uid, value)
