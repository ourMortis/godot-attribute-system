class_name AttributeSlot extends RefCounted
## 一个实体上, 某一个属性的运行时状态
##
## ★ 只有"状态 + 记账", 不做计算:
##   定义在 AttributeDefinition, 计算在 AttributeEvaluator, 桶规则在 BucketSpec / AttributeFormula
##
## 关于"脏": 输入变化时由 AttributeSheet 负责把本槽及所有下游依赖标脏;
## 求值只处理脏槽, 未受影响的属性保持缓存.
var definition: AttributeDefinition
var base_value: float = 0.0 ## 裸值: 只被成长 / 即时效果修改, 派生贡献永远不写回这里
var modifiers: Array[AttributeModifier] = [] ## 当前挂在身上的修改器(来源每叠一层就是一份拷贝)
var cached_value: float = 0.0 ## 最近一次计算的缓存
var computed_revision: int = -1 ## 最近一次计算对应的 sheet.revision(防环占位与调试用)
var dirty: bool = true ## 是否需要重算

func _init(definition_ref: AttributeDefinition) -> void:
	definition = definition_ref
	base_value = definition_ref.default_base
	cached_value = definition_ref.default_base

func get_id() -> StringName:
	return definition.id

## 缓存是否过期(脏)
func is_dirty() -> bool:
	return dirty

func mark_clean(revision: int, value: float) -> void:
	computed_revision = revision
	cached_value = value
	dirty = false

func mark_dirty() -> void:
	dirty = true

func set_base_value(value: float) -> void:
	base_value = value

func add_modifier(modifier: AttributeModifier) -> void:
	if modifier:
		modifiers.append(modifier)

func remove_modifier(modifier: AttributeModifier) -> bool:
	var index: int = modifiers.find(modifier)
	if index < 0:
		return false
	modifiers.remove_at(index)
	return true

## 摘掉某个来源贡献的所有修改器, 返回摘掉的数量
func remove_modifiers_from(source_id: StringName) -> int:
	var removed: int = 0
	for i in range(modifiers.size() - 1, -1, -1):
		if modifiers[i].source_id == source_id:
			modifiers.remove_at(i)
			removed += 1
	return removed

## 按 uid 查找修改器(uid 为空时找不到)
func find_modifier(modifier_uid: StringName) -> AttributeModifier:
	if modifier_uid == &"":
		return null
	for modifier: AttributeModifier in modifiers:
		if modifier.modifier_uid == modifier_uid:
			return modifier
	return null

## 只保存"永久值", 派生值与缓存都可以由定义重新算出来
func snapshot() -> Dictionary:
	return {"base_value": base_value}
