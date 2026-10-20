@tool
class_name AttributeDependency extends Resource
## 一条"我的基础值依赖另一个属性"的声明
##
## ★ 只存"源属性的 id + 怎么取", 不存 Attribute 引用:
##   定义资源必须能被多个实体共享, 存引用会把定义绑死到某个实例上.
enum DependencyMode {
	WEIGHTED, ## 贡献 = coefficient * 源属性当前值 (常用)
	RAW,      ## 贡献 = 源属性当前值 (忽略 coefficient)
}

@export var source_id: StringName = &"" ## 被依赖属性的 id
@export var coefficient: float = 1.0
@export var mode: DependencyMode = DependencyMode.WEIGHTED
@export var optional: bool = false ## 源属性不存在时: true = 按 0 处理, false = 加载期报错
@export var enabled: bool = true ## 临时开关: 关闭后这条依赖不参与计算
@export var transform: AttributeFormula ## 可选: 对源值做单值变换(如护甲减伤 x / (x + K))

## 单值变换用的空参数, 避免每次调用都构造容器
var _empty_buckets: Array[BucketSpec] = []
var _empty_bucket_values: Dictionary[StringName, float] = {}

## 这条依赖对基础值的贡献
func contribution(source_value: float) -> float:
	if not enabled:
		return 0.0
	var value: float = source_value
	if transform:
		value = transform.calculate(value, _empty_buckets, _empty_bucket_values)
	if mode == DependencyMode.RAW:
		return value
	return coefficient * value

func validate() -> String:
	if source_id == &"":
		return "依赖缺少 source_id"
	if not is_finite(coefficient):
		return "依赖的 coefficient 非法"
	return ""

func describe() -> String:
	if mode == DependencyMode.WEIGHTED:
		return "%s(x%s)" % [source_id, coefficient]
	return "%s(raw)" % source_id
