class_name AttributeFormulaNormal extends AttributeFormula
## 默认策略: 严格按定义里桶的顺序, 逐个把桶折叠进有效基础值
##
## 例: buckets = [ flat(ADD), increased(MULTIPLY_ONE_PLUS), more(MULTIPLY) ]
##     value = base -> +Σflat -> *(1 + Σincreased) -> *Πmore
## 空桶不参与计算(覆盖区没有修改器时不会把结果清成 0)
func calculate(effective_base: float, buckets: Array[BucketSpec], bucket_values: Dictionary[StringName, float]) -> float:
	return BucketSpec.fold_all(effective_base, buckets, bucket_values)
