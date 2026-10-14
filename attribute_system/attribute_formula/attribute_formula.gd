@abstract class_name AttributeFormula extends Resource
## 仅存储属性的计算策略
## 通过 calculate 接口使用
## 配合 AttributeModifier 的 tag 成员可实现复杂运算规则

@abstract
func calculate(value: float, modifiers: Array[AttributeModifier]) -> float
