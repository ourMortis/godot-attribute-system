class_name AttributeFormulaInstant extends AttributeFormula

## 配合InstantAttribute实现永久生效的修改器 因为不保存这种修改器 所以数组长度总是1
func calculate(value: float, modifiers: Array[AttributeModifier]) -> float:
	match modifiers[0].type:
		AttributeModifier.ModifierType.ADD:
			return value + modifiers[0].value
		AttributeModifier.ModifierType.MUL:
			return value * modifiers[0].value
		AttributeModifier.ModifierType.SET:
			return modifiers[0].value
	return value
