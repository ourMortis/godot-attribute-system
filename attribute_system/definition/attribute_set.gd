@tool
class_name AttributeSet extends Resource
## 一份属性配置集: 定义列表 + 共享的求值计划缓存
##
## 每个实体类型通常只引用一份 AttributeSet(例如 player.tres / enemy.tres).
## 所有引用同一份 AttributeSet 的 AttributeSystem 共享同一个 EvaluationPlan,
## 计划只在第一次使用时编译一次, 之后直接复用.
##
## 定义在运行期视为不可变; 如果在工具脚本里修改了定义, 调用 invalidate() 使缓存失效.
@export var definitions: Array[AttributeDefinition] = []

var _plan: EvaluationPlan
var _evaluator: AttributeEvaluator

## 取得(必要时编译并缓存)求值计划
## 编辑器里不缓存, 保证每次校验都基于最新配置
func get_plan() -> EvaluationPlan:
	if not Engine.is_editor_hint() and _plan:
		return _plan
	var result := EvaluationPlan.new()
	var errors := result.compile(definitions)
	if not Engine.is_editor_hint():
		for error: String in errors:
			push_error("[AttributeSet] %s" % error)
		_plan = result
	return result

## 取得共享求值器(无实体状态, 可被多个实体共用)
func get_evaluator() -> AttributeEvaluator:
	var current_plan := get_plan()
	if Engine.is_editor_hint():
		return AttributeEvaluator.new(current_plan)
	if not _evaluator or _evaluator.plan != current_plan:
		_evaluator = AttributeEvaluator.new(current_plan)
	return _evaluator

## 清空缓存(仅在运行期修改定义后需要)
func invalidate() -> void:
	_plan = null
	_evaluator = null

## 校验配置(不写入缓存)
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if definitions.is_empty():
		errors.append("没有配置任何属性定义")
	var check_plan := EvaluationPlan.new()
	errors.append_array(check_plan.compile(definitions))
	return errors

func has_definition(attribute_id: StringName) -> bool:
	return get_definition(attribute_id) != null

func get_definition(attribute_id: StringName) -> AttributeDefinition:
	for definition: AttributeDefinition in definitions:
		if definition and definition.id == attribute_id:
			return definition
	return null

func get_definition_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for definition: AttributeDefinition in definitions:
		if definition and not ids.has(definition.id):
			ids.append(definition.id)
	return ids
