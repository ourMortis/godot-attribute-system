class_name AttributeModifier extends Resource

enum ModifierType{ADD, MUL, SET}

var modifier_uid: String
var type: ModifierType
var tag: int 	# 配合AttributeFormula来实现复杂运算规则
var value: float
