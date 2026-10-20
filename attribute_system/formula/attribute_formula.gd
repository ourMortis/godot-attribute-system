@abstract class_name AttributeFormula extends Resource
## 属性的计算策略: 决定"各桶的聚合结果如何组合成最终值"
##
## 契约(三个参数都与定义中桶的顺序一致):
##   effective_base : 裸值 + 全部依赖贡献
##   buckets        : 该属性声明的桶(有序), 里面带有 combine 规则
##   bucket_values  : 各桶的聚合结果, 只包含"有修改器参与"的桶
##
## 约定: AttributeDependency.transform 做单值变换时, buckets 与 bucket_values 都为空,
##       effective_base 就是被变换的那个值.
##
## 常规属性直接用 AttributeFormulaNormal(或者留空, 求值器会退化为"按桶顺序折叠");
## 只有需要软上限 / 非线性曲线 / 条件规则这类特殊算法时, 才自己实现一个子类.
@abstract
func calculate(effective_base: float, buckets: Array[BucketSpec], bucket_values: Dictionary[StringName, float]) -> float
