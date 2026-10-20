class_name AttributeSheet extends RefCounted
## 一个实体的属性表: 定义(共享) + 槽(独占) + 来源(独占) + 版本号 + 事件
##
## ★ 这是"定义与实例分离"的落点: 同一套定义可以生成任意多张表, 彼此状态互不影响
## ★ 变更会把受影响的槽及其所有下游依赖标脏, 求值时只重算脏槽
signal on_value_changed(attribute_id: StringName, old_value: float, new_value: float)
signal on_source_applied(source_id: StringName)
signal on_source_removed(source_id: StringName)

var plan: EvaluationPlan
var evaluator: AttributeEvaluator
var slots: Dictionary[StringName, AttributeSlot] = {}
var sources: Dictionary[StringName, ModifierSource] = {}
var revision: int = 0
var auto_refresh: bool = true ## true: 变更后立刻重算并广播; false: 读取时才惰性重算

var _batch_depth: int = 0
var _dirty_ids: Dictionary[StringName, bool] = {} ## 需要重算的属性集合

func _init(plan_ref: EvaluationPlan, evaluator_ref: AttributeEvaluator, auto_refresh_: bool = true) -> void:
	plan = plan_ref
	evaluator = evaluator_ref
	auto_refresh = auto_refresh_
	build_slots()
	# 建表时先算一遍: 让缓存一开始就是真实值(首次求值不会广播事件)
	refresh()

## 按计划重建所有槽(热拔插定义集合后由 AttributeSystem 调用)
func build_slots() -> void:
	slots.clear()
	_dirty_ids.clear()
	if not plan:
		return
	for definition: AttributeDefinition in plan.definitions:
		if not definition:
			continue
		slots[definition.id] = AttributeSlot.new(definition)
		_dirty_ids[definition.id] = true

# ---------------------------------------------------------------- 查询

func has(attribute_id: StringName) -> bool:
	return slots.has(attribute_id)

func get_slot(attribute_id: StringName) -> AttributeSlot:
	var slot: AttributeSlot = slots.get(attribute_id)
	return slot

func get_definition(attribute_id: StringName) -> AttributeDefinition:
	var slot: AttributeSlot = slots.get(attribute_id)
	return slot.definition if slot else null

## 取当前值(惰性: 过期才会重算)
func get_value(attribute_id: StringName) -> float:
	return evaluator.value_of(slots, revision, attribute_id)

func get_base_value(attribute_id: StringName) -> float:
	var slot: AttributeSlot = slots.get(attribute_id)
	if not slot:
		push_error("[AttributeSheet] 属性不存在: %s" % attribute_id)
		return 0.0
	return slot.base_value

## 修改裸值(升级加点 / 初始化这类永久改动走这里)
func set_base_value(attribute_id: StringName, value: float) -> void:
	var slot: AttributeSlot = slots.get(attribute_id)
	if not slot:
		push_error("[AttributeSheet] 属性不存在: %s" % attribute_id)
		return
	slot.set_base_value(value)
	mark_changed([attribute_id])

func get_attribute_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for attribute_id: StringName in slots:
		ids.append(attribute_id)
	return ids

# ---------------------------------------------------------------- 来源

## 施加一个来源. clone_source = true(默认)时会先深拷贝, 避免来源模板被多次施加时互相污染
func apply_source(source: ModifierSource, clone_source: bool = true) -> bool:
	if not source:
		push_error("[AttributeSheet] apply_source 收到 null")
		return false
	var instance: ModifierSource = source.clone() if clone_source else source
	if not instance.enabled:
		return false
	if instance.instant:
		return _apply_instant_source(instance)
	if instance.source_id == &"":
		push_error("[AttributeSheet] 来源缺少 source_id")
		return false
	var existing: ModifierSource = sources.get(instance.source_id)
	var affected: Array[StringName] = _source_targets(existing)
	affected.append_array(_source_targets(instance))
	# 同名来源再次施加: 可叠层的加一层, 不可叠层的刷新覆盖
	if existing and existing.stackable and instance.stackable:
		instance.stack_count = existing.stack_count + 1
	instance.stack_count = maxi(instance.stack_count, 1)
	instance.remaining_time = instance.duration
	_clear_source_modifiers(instance.source_id)
	sources[instance.source_id] = instance
	_push_source_modifiers(instance)
	if not existing:
		on_source_applied.emit(instance.source_id)
	mark_changed(affected)
	return true

## 撤销一个来源, 它贡献的所有修改器会被整体摘掉
func remove_source(source_id: StringName) -> bool:
	var source: ModifierSource = sources.get(source_id)
	if not source:
		return false
	var affected: Array[StringName] = _source_targets(source)
	sources.erase(source_id)
	_clear_source_modifiers(source_id)
	on_source_removed.emit(source_id)
	mark_changed(affected)
	return true

func has_source(source_id: StringName) -> bool:
	return sources.has(source_id)

func get_source(source_id: StringName) -> ModifierSource:
	var source: ModifierSource = sources.get(source_id)
	return source

func get_source_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for source_id: StringName in sources:
		ids.append(source_id)
	return ids

## 调整叠层数(0 等于撤销这个来源)
func set_source_stack(source_id: StringName, count: int) -> bool:
	var source: ModifierSource = sources.get(source_id)
	if not source:
		return false
	var affected: Array[StringName] = _source_targets(source)
	source.stack_count = maxi(count, 0)
	_clear_source_modifiers(source_id)
	if source.stack_count == 0:
		sources.erase(source_id)
		on_source_removed.emit(source_id)
	else:
		_push_source_modifiers(source)
	mark_changed(affected)
	return true

## 修改来源内某条修改器的数值(需要该修改器有 modifier_uid)
func set_modifier_value(source_id: StringName, modifier_uid: StringName, value: float) -> bool:
	if modifier_uid == &"":
		return false
	var source: ModifierSource = sources.get(source_id)
	if not source:
		return false
	var affected: Array[StringName] = _source_targets(source)
	for modifier: AttributeModifier in source.modifiers:
		if modifier.modifier_uid == modifier_uid:
			modifier.value = value
			_clear_source_modifiers(source_id)
			_push_source_modifiers(source)
			mark_changed(affected)
			return true
	return false

## 推进限时来源
func tick(delta: float) -> void:
	var expired: Array[StringName] = []
	for source_id: StringName in sources:
		var source: ModifierSource = sources[source_id]
		source.tick(delta)
		if source.is_expired():
			expired.append(source_id)
	if expired.is_empty():
		return
	begin_batch()
	for source_id: StringName in expired:
		remove_source(source_id)
	end_batch()

# ---------------------------------------------------------------- 事务 / 刷新

func begin_batch() -> void:
	_batch_depth += 1

## 一批修改结束时统一重算一轮, 只广播一轮事件, 避免下游读到中间态
func end_batch() -> void:
	_batch_depth = maxi(_batch_depth - 1, 0)
	if _batch_depth == 0 and auto_refresh:
		refresh()

func refresh() -> void:
	if _dirty_ids.is_empty():
		return
	var pending: Array[StringName] = []
	for attribute_id: StringName in _dirty_ids:
		pending.append(attribute_id)
	_dirty_ids.clear()
	evaluator.refresh_dirty(slots, revision, pending, _on_evaluated)

# ---------------------------------------------------------------- 持久化 / 热拔插

## 只导出持久属性的裸值; 派生值 / 缓存 / 事件都不需要也不应该入档
func snapshot() -> Dictionary:
	var data: Dictionary = {}
	for slot: AttributeSlot in slots.values():
		if slot.definition.persist:
			data[String(slot.definition.id)] = slot.base_value
	return data

func restore(data: Dictionary) -> void:
	begin_batch()
	var restored: Array[StringName] = []
	for key: Variant in data:
		var slot: AttributeSlot = slots.get(StringName(key))
		if not slot:
			continue
		slot.set_base_value(float(data[key]))
		restored.append(slot.get_id())
	if not restored.is_empty():
		mark_changed(restored)
	end_batch()

func dump() -> String:
	var lines := PackedStringArray()
	if not plan:
		return ""
	for attribute_id: StringName in plan.order:
		var slot: AttributeSlot = slots.get(attribute_id)
		if not slot:
			continue
		lines.append("  %-12s base=%-8s cur=%-8s" % [attribute_id, slot.base_value, get_value(attribute_id)])
	for source_id: StringName in sources:
		lines.append(sources[source_id].describe())
	return "\n".join(lines)

# ---------------------------------------------------------------- 内部

## 标记受影响的属性及其下游依赖为脏
func mark_changed(affected_ids: Array) -> void:
	if affected_ids.is_empty():
		return
	revision += 1
	for attribute_id: StringName in affected_ids:
		_propagate_dirty(attribute_id)
	if auto_refresh and _batch_depth == 0:
		refresh()

func _on_evaluated(attribute_id: StringName, old_value: float, new_value: float) -> void:
	on_value_changed.emit(attribute_id, old_value, new_value)

## 即时来源: 直接折算进裸值, 不留任何记录
func _apply_instant_source(source: ModifierSource) -> bool:
	var touched: Array[StringName] = []
	for layer: int in maxi(source.stack_count, 1):
		for modifier: AttributeModifier in source.modifiers:
			var slot: AttributeSlot = slots.get(modifier.target_id)
			if not slot:
				push_warning("[AttributeSheet] 即时来源 %s 指向不存在的属性: %s" % [source.source_id, modifier.target_id])
				continue
			slot.set_base_value(AttributeModifier.apply(slot.base_value, modifier.op, modifier.value))
			touched.append(modifier.target_id)
	if not touched.is_empty():
		mark_changed(touched)
	return not touched.is_empty()

## 沿依赖图标脏: 当前属性 + 所有下游
func _propagate_dirty(attribute_id: StringName) -> void:
	var pending: Array[StringName] = [attribute_id]
	while not pending.is_empty():
		var current: StringName = pending.pop_back()
		var slot: AttributeSlot = slots.get(current)
		if not slot or slot.is_dirty():
			continue
		slot.mark_dirty()
		_dirty_ids[current] = true
		if plan:
			for dependent: StringName in plan.dependents_of.get(current, []):
				pending.append(dependent)

## 来源实际影响到哪些属性
func _source_targets(source: ModifierSource) -> Array[StringName]:
	var ids: Array[StringName] = []
	if not source:
		return ids
	for modifier: AttributeModifier in source.modifiers:
		if modifier and not ids.has(modifier.target_id):
			ids.append(modifier.target_id)
	return ids

## 把来源的修改器入账到各槽, layers < 0 表示按 stack_count 铺满
func _push_source_modifiers(source: ModifierSource, layers: int = -1) -> void:
	var count: int = source.stack_count if layers < 0 else layers
	for layer: int in maxi(count, 0):
		for modifier: AttributeModifier in source.modifiers:
			var slot: AttributeSlot = slots.get(modifier.target_id)
			if not slot:
				push_warning("[AttributeSheet] 来源 %s 指向不存在的属性: %s" % [source.source_id, modifier.target_id])
				continue
			var copy: AttributeModifier = modifier.clone()
			copy.source_id = source.source_id
			slot.add_modifier(copy)

func _clear_source_modifiers(source_id: StringName) -> void:
	for slot: AttributeSlot in slots.values():
		slot.remove_modifiers_from(source_id)
