@tool
class_name AttributeDefinition extends Resource
## 属性的"是什么": 一份静态定义, 可被多个实体共享, 运行期只读
##
## ★ 不存运行时值 / 缓存 / 对象引用.
##   值由 AttributeSlot 承载, 计算由 AttributeEvaluator 执行, 桶规则由 BucketSpec 描述.
enum RoundingMode {
	NONE,  ## 不取整
	ROUND, ## 四舍五入
	FLOOR, ## 向下取整
	CEIL,  ## 向上取整
}

@export var id: StringName = &"" ## 唯一标识, 属性之间互相引用只认它
@export var display_name: String = "" ## 展示名(UI / 调试)
@export var default_base: float = 0.0 ## 裸值默认值, 创建 AttributeSlot 时使用

@export var buckets: Array[BucketSpec] = [] ## 有序桶列表: 数组顺序 = 计算顺序
@export var formula: AttributeFormula ## 计算策略; 为空则退化为"严格按桶顺序折叠"
@export var dependencies: Array[AttributeDependency] = [] ## 派生来源声明

@export var clamp_enabled: bool = false ## 是否钳制最终值
@export var clamp_min: float = 0.0
@export var clamp_max: float = 0.0

@export var rounding: RoundingMode = RoundingMode.NONE ## 最终值取整方式
@export var tags: Array[StringName] = [] ## 查询 / UI 分类用
@export var accept_tags: Array[StringName] = [] ## 非空时, 只有标签命中的修改器才被接受
@export var persist: bool = true ## 是否写入存档(派生属性一般填 false)

## 是否存在这个桶
func has_bucket(bucket_name: StringName) -> bool:
	return get_bucket(bucket_name) != null

## 取桶规格(找不到返回 null)
func get_bucket(bucket_name: StringName) -> BucketSpec:
	for bucket: BucketSpec in buckets:
		if bucket and bucket.bucket_name == bucket_name:
			return bucket
	return null

## 这条修改器是否作用于我
func accepts(modifier: AttributeModifier) -> bool:
	if not modifier or not has_bucket(modifier.bucket):
		return false
	if accept_tags.is_empty():
		return true
	for tag: StringName in modifier.tags:
		if accept_tags.has(tag):
			return true
	return false

## 把"基础值 + 各桶聚合结果"算成最终值
func fold(effective_base: float, bucket_values: Dictionary[StringName, float]) -> float:
	if formula:
		return formula.calculate(effective_base, buckets, bucket_values)
	return BucketSpec.fold_all(effective_base, buckets, bucket_values)

## 收尾: 钳制 + 取整
func finalize(value: float) -> float:
	var result: float = value
	if clamp_enabled:
		result = clampf(result, clamp_min, clamp_max)
	match rounding:
		RoundingMode.ROUND:
			result = roundf(result)
		RoundingMode.FLOOR:
			result = floorf(result)
		RoundingMode.CEIL:
			result = ceilf(result)
	return result

## 自检: 返回所有问题描述(空数组 = 没问题)
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("缺少 id")
	var seen_buckets: Dictionary[StringName, bool] = {}
	for bucket: BucketSpec in buckets:
		if not bucket:
			errors.append("桶列表里存在 null")
		elif bucket.bucket_name == &"":
			errors.append("存在没有名字的桶")
		elif seen_buckets.has(bucket.bucket_name):
			errors.append("桶名重复: %s" % bucket.bucket_name)
		else:
			seen_buckets[bucket.bucket_name] = true
	for dependency: AttributeDependency in dependencies:
		if not dependency:
			errors.append("依赖列表里存在 null")
			continue
		var message: String = dependency.validate()
		if message:
			errors.append(message)
	if clamp_enabled and clamp_min > clamp_max:
		errors.append("clamp_min 大于 clamp_max")
	return errors
