class_name AttributeEvaluator extends RefCounted
## 求值器: 按 EvaluationPlan 的顺序, 把"定义 + 槽状态"算成数值
##
## ★ 只持有计划, 不持有任何实体状态, 因此可以被所有实体共享
## ★ 有意不引用 AttributeSheet(只认"槽表 + 版本号 + 通知回调"), 让类依赖保持无环
## ★ 惰性: 只有 slot.is_dirty() 时才真正重算
var plan: EvaluationPlan
var _reported: Dictionary[StringName, bool] = {} ## 已经报过错的属性, 避免每帧刷屏

func _init(plan_ref: EvaluationPlan) -> void:
	plan = plan_ref

## 惰性取当前值: 必要时按依赖递归重算
func value_of(slots: Dictionary[StringName, AttributeSlot], revision: int, attribute_id: StringName) -> float:
	var slot: AttributeSlot = slots.get(attribute_id)
	if not slot:
		_report(attribute_id, "取值失败, 属性不存在: %s" % attribute_id)
		return 0.0
	if slot.is_dirty():
		_evaluate(slots, revision, slot, Callable())
	return slot.cached_value

## 强制重算单个属性(依赖会按需先算)
func refresh(slots: Dictionary[StringName, AttributeSlot], revision: int, attribute_id: StringName, on_changed: Callable = Callable()) -> void:
	var slot: AttributeSlot = slots.get(attribute_id)
	if not slot:
		_report(attribute_id, "刷新失败, 属性不存在: %s" % attribute_id)
		return
	_evaluate(slots, revision, slot, on_changed)

## 按计划顺序刷新所有过期的属性
func refresh_all(slots: Dictionary[StringName, AttributeSlot], revision: int, on_changed: Callable = Callable()) -> void:
	if not plan:
		return
	for attribute_id: StringName in plan.order:
		var slot: AttributeSlot = slots.get(attribute_id)
		if slot and slot.is_dirty():
			_evaluate(slots, revision, slot, on_changed)

## 只刷新给定的脏属性; 依赖会按需递归先算
func refresh_dirty(slots: Dictionary[StringName, AttributeSlot], revision: int, dirty_ids: Array[StringName], on_changed: Callable = Callable()) -> void:
	for attribute_id: StringName in dirty_ids:
		var slot: AttributeSlot = slots.get(attribute_id)
		if slot and slot.is_dirty():
			_evaluate(slots, revision, slot, on_changed)

## 单个属性的求值过程
func _evaluate(slots: Dictionary[StringName, AttributeSlot], revision: int, slot: AttributeSlot, on_changed: Callable) -> void:
	var definition: AttributeDefinition = slot.definition
	var old_value: float = slot.cached_value
	# 首次求值不算"变更": 之前没有任何观察到的值, 不该给监听者发一条假事件
	var was_computed: bool = slot.computed_revision != -1
	# 先标记成本轮已算过: 万一还有环(正常已被 plan 拦下), 递归回读会拿到旧值而不是无限递归
	slot.mark_clean(revision, old_value)

	# 第一步: 裸值 + 依赖贡献 = 有效基础值
	var effective_base: float = slot.base_value
	for dependency: AttributeDependency in definition.dependencies:
		if not dependency or not dependency.enabled:
			continue
		if slots.has(dependency.source_id):
			effective_base += dependency.contribution(value_of(slots, revision, dependency.source_id))
		elif not dependency.optional:
			_report(definition.id, "属性 %s 依赖的源不存在: %s" % [definition.id, dependency.source_id])

	# 第二步: 按桶聚合修改器
	var bucket_values: Dictionary[StringName, float] = _aggregate(definition, slot.modifiers)

	# 第三步: 交给策略算最终值, 最后做钳制与取整
	var new_value: float = definition.finalize(definition.fold(effective_base, bucket_values))
	slot.mark_clean(revision, new_value)
	if on_changed.is_valid() and was_computed and not is_equal_approx(old_value, new_value):
		on_changed.call(definition.id, old_value, new_value)

## 把修改器按桶聚合: 只有被修改器碰过的桶才会进入结果
func _aggregate(definition: AttributeDefinition, modifiers: Array[AttributeModifier]) -> Dictionary[StringName, float]:
	var bucket_values: Dictionary[StringName, float] = {}
	for modifier: AttributeModifier in modifiers:
		if definition.accepts(modifier):
			var bucket: BucketSpec = definition.get_bucket(modifier.bucket)
			var accumulated: float = bucket_values.get(modifier.bucket, bucket.seed_value())
			bucket_values[modifier.bucket] = AttributeModifier.apply(accumulated, modifier.op, modifier.value)
	return bucket_values

func _report(attribute_id: StringName, message: String) -> void:
	if _reported.has(attribute_id):
		return
	_reported[attribute_id] = true
	push_error("[AttributeEvaluator] %s" % message)
