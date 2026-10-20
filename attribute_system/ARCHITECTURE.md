# 属性系统架构说明

本文档描述 `attribute_system` 目录下这套属性系统的结构、职责划分与运行流程。
使用步骤、配置示例、运行时 API 与常见问题见 [USAGE.md](USAGE.md)。

系统目标：

- **逐实体**：每个玩家 / 敌人 / 生物在自己的场景树里挂一个 `AttributeSystem`，状态互不影响。
- **数据驱动**：属性、桶、公式都是资源，可以在检查器里装配。
- **支持派生属性**：一个属性的基础值可以依赖其它属性，并自动随上游变化。
- **修改可撤销**：所有数值改动都来自一个"来源"（装备 / buff / 天赋 / 即时结算）。
- **计算方式自由**：每个属性可以选择自己的桶与计算策略。

---

## 1. 目录结构

```
attribute_system/
├── ARCHITECTURE.md
├── attribute_system.gd               # 门面节点：每个实体一个
│
├── definition/                       # 静态定义与配置集（可共享）
│   ├── attribute_set.gd
│   ├── attribute_definition.gd
│   ├── attribute_dependency.gd
│   └── bucket_spec.gd
│
├── formula/                          # 属性的计算策略
│   ├── attribute_formula.gd
│   ├── attribute_formula_normal.gd
│   └── attribute_formula_multiplication_area.gd
│
├── modifier/                         # 修改记录与修改来源
│   ├── attribute_modifier.gd
│   └── modifier_source.gd
│
├── runtime/                          # 每个实体的运行时状态
│   ├── attribute_slot.gd
│   └── attribute_sheet.gd
│
└── evaluation/                       # 求值计划与执行
	├── evaluation_plan.gd
	└── attribute_evaluator.gd
```

目录划分对应一条单向依赖链：

```
definition ─► formula
modifier ───► runtime ───► evaluation ───► attribute_system.gd
```

每个 `.gd` 旁边的 `.uid` 由 Godot 生成，用于资源引用，不要手动修改。

---

## 2. 设计原则

1. **定义与实例分离**
   `definition/` 下的资源描述"属性是什么"，可被所有实体共享且运行期只读；
   `runtime/` 下的对象保存"这个实体现在是多少"，每个实体独占。

2. **逐实体组件**
   一个实体一个 `AttributeSystem` 节点，该节点只持有一张 `AttributeSheet`。
   它不是单例，也不管理其它实体。玩家与敌人可以引用同一批定义资源，但裸值、来源、缓存互相独立。

3. **配置期自由、运行期固定**
   属性、桶、公式、依赖都在编辑器中以资源形式自由装配；进入运行期后定义视为不可变，
   求值计划按 `AttributeSet` 缓存、只编译一次，不支持运行期增删属性。

4. **单向依赖**
   属性之间只用 `id` 引用，不存对象引用；类之间只依赖下一层，整体构成有向无环图。

5. **所有数值变更经过来源**
   数值只能通过 `ModifierSource → AttributeModifier` 进入系统（裸值的显式设置除外），
   这样撤销、溯源、回放才有依据。

6. **顺序显式且无环**
   桶的数组顺序就是计算顺序；属性依赖在加载期做拓扑排序与环检测。

7. **脏传播 + 惰性重算**
   变更会把受影响的槽及所有下游依赖标脏；求值只处理脏槽。
   `revision` 记录计算轮次，并用于首次计算与防环占位。

### 性能特征

- 一次变更的传播成本与"受影响属性的下游子图"成正比，而不是与属性总数成正比。
- 求值只处理脏槽；未受影响的属性直接读缓存。
- 信号转发是每个变化事件一次额外的 `emit`，成本远低于一次属性求值；
  高频场景可以用批量事务合并事件，或直接连接 `AttributeSheet` 的表级信号。

---

## 3. 类总览

| 类 | 所在目录 | 基类 | 职责 | 每实体独占 |
| --- | --- | --- | --- | --- |
| `AttributeSet` | `definition/` | `Resource` | 一份属性配置集：定义列表 + 共享的求值计划缓存 | 否（只读共享） |
| `AttributeDefinition` | `definition/` | `Resource` | 属性定义：id、默认裸值、桶、依赖、公式、钳制、取整 | 否（只读共享） |
| `AttributeDependency` | `definition/` | `Resource` | 一条依赖声明：源 id、系数、取值模式、可选变换 | 否（只读共享） |
| `BucketSpec` | `definition/` | `Resource` | 一个桶 / 乘区的规格与折叠规则 | 否（只读共享） |
| `AttributeFormula` | `formula/` | `Resource` | 计算策略：把各桶结果组合成最终值 | 否（只读共享） |
| `AttributeModifier` | `modifier/` | `Resource` | 一条修改记录：目标属性、桶、操作、数值、来源 | 随来源复制 |
| `ModifierSource` | `modifier/` | `RefCounted` | 一次修改的来源：叠层、计时、即时生效 | 是 |
| `AttributeSlot` | `runtime/` | `RefCounted` | 某实体某属性的状态：裸值、修改器、缓存、版本 | 是 |
| `AttributeSheet` | `runtime/` | `RefCounted` | 某实体的属性表：槽 + 来源 + 版本 + 事件 | 是 |
| `EvaluationPlan` | `evaluation/` | `Resource` | 加载期编译出的求值顺序与环检测结果 | 否（只读共享） |
| `AttributeEvaluator` | `evaluation/` | `RefCounted` | 按计划把"定义 + 槽"算成数值 | 否（无状态共享） |
| `AttributeSystem` | 根目录 | `Node` | 本实体的门面：装配定义、建表、转发调用、派发事件 | 是（每个实体一个） |

---

## 4. 计算流水线

单个属性的求值过程：

```
effective_base = slot.base_value
			   + Σ 每条依赖的贡献
bucket_values  = 各桶的修改器聚合结果（只含被修改器碰过的桶）
value          = definition.fold(effective_base, bucket_values)
value          = definition.finalize(value)        # clamp + 取整
```

### 4.1 依赖贡献

每条 `AttributeDependency`：

```
contribution = coefficient × source_value        # WEIGHTED（默认）
contribution = source_value                      # RAW
```

可选的 `transform` 会先对源值做单值变换（例如护甲减伤 `x / (x + K)`）。

### 4.2 桶

桶内的修改器统一按 `AttributeModifier.apply()` 聚合：

```
ADD      -> 累加
MUL      -> 累乘
OVERRIDE -> 覆盖
```

桶的聚合起点由 `BucketSpec.seed_value()` 决定（乘法桶为 1，其余为 0），聚合结果按 `combine` 并入当前值：

| `combine` | 并入方式 | 典型用途 |
| --- | --- | --- |
| `ADD` | `当前值 + Σ` | 平坦加法区 |
| `MULTIPLY` | `当前值 × Π` | 独立乘区 |
| `MULTIPLY_ONE_PLUS` | `当前值 × (1 + Σ)` | 百分比加算区 |
| `OVERRIDE` | `当前值 = 桶内值` | 覆盖区 |

没有被修改器碰过的桶不会进入 `bucket_values`，因此空桶不影响结果（空的覆盖区不会把值清成 0）。

### 4.3 公式

`AttributeFormula.calculate(effective_base, buckets, bucket_values)` 负责"怎么组合"：

- `AttributeFormulaNormal`：严格按桶顺序折叠（默认策略）。
- `AttributeFormulaMultiplicationArea`：所有桶都按乘区处理。
- 自定义子类：软上限、非线性曲线、条件规则等。

`AttributeDefinition.formula` 为空时退化为"按桶顺序折叠"。

---

## 5. 逐类说明

### 5.1 `AttributeDefinition`（属性定义）

**存**：`id`、`display_name`、`default_base`、`buckets`、`dependencies`、`formula`、
`clamp_enabled / clamp_min / clamp_max`、`rounding`、`tags`、`accept_tags`、`persist`。

**做**：`validate()` 自检、`get_bucket()` 查桶、`accepts(modifier)` 判断修改器是否生效、
`fold()` 调用计算公式、`finalize()` 钳制与取整。

**边界**：不存运行时值、缓存或对象引用，运行期只读。

### 5.2 `AttributeDependency`（依赖声明）

**存**：`source_id`、`coefficient`、`mode`、`optional`、`enabled`、`transform`。

**做**：`contribution(source_value)` 返回这条依赖对基础值的贡献。

**边界**：只描述"取谁、怎么取"，解析与排序由 `EvaluationPlan` 负责。

### 5.3 `BucketSpec`（桶规格）

**存**：`bucket_name`、`combine`、`description`。

**做**：`seed_value()`、`combine_value()`；静态方法 `fold_all()` 提供默认折叠流水线。

**边界**：只描述一个桶，不知道具体属性，也不持有修改器。

### 5.4 `AttributeFormula`（计算策略）

**存**：无运行时状态。子类可按需增加导出参数。

**做**：`calculate(effective_base, buckets, bucket_values)` 返回最终值。

**约定**：依赖的 `transform` 做单值变换时，`buckets` 与 `bucket_values` 为空，
`effective_base` 就是被变换的值。

### 5.5 `AttributeModifier`（修改记录）

**存**：`modifier_uid`、`op`、`bucket`、`value`、`target_id`、`source_id`、`tags`。

**做**：静态方法 `apply(current, op, amount)` 是唯一的"作用到数值上"的入口；
`clone()` 用于入账前深拷贝。

**边界**：只描述数据，不含计算逻辑，也不知道自己属于哪个实体的表。

### 5.6 `ModifierSource`（修改来源）

**存**：`source_id`、`display_name`、`modifiers`、`tags`、`instant`、`stackable`、
`stack_count`、`duration`、`remaining_time`、`enabled`。

**做**：`create()` / `add()` 构造来源，`clone()` 深拷贝，`tick()` 推进计时，`is_expired()` 判断到期。

**行为**：

- 持续来源施加后保留在 `AttributeSheet.sources` 中，可按 `source_id` 整体撤销。
- `stackable` 来源重复施加会叠层，每层完整贡献一遍修改器。
- `instant` 来源直接把修改折算进 `base_value`，不保留记录，适合"当前生命值"这类一次性改动。

### 5.7 `AttributeSlot`（属性槽）

**存**：`definition`（共享引用）、`base_value`（本实体裸值）、`modifiers`、
`cached_value`、`computed_revision`、`dirty`。

**做**：修改器入账 / 出账、按来源批量清理、按 uid 查找、缓存读写，
以及 `is_dirty()` / `mark_dirty()` / `mark_clean()`。

**边界**：不做计算；不持有 `AttributeSheet` 引用（避免引用环）。

`base_value` 只承载永久值（成长、即时效果）。派生贡献不写回它，否则会累积且无法撤销。

### 5.8 `AttributeSheet`（实体属性表）

**存**：`plan`、`evaluator`、`slots`、`sources`、`revision`、`auto_refresh`、批量深度。

**做**：

- 查询与修改：`get_value()`、`get_base_value()`、`set_base_value()`。
- 来源：`apply_source()`、`remove_source()`、`set_source_stack()`、`set_modifier_value()`、`tick()`。
- 脏传播：`mark_changed(affected_ids)` 标记目标属性及其所有下游；刷新只处理 `_dirty_ids` 中的槽。
- 事务：`begin_batch()` / `end_batch()`，一批修改只在结束时重算并广播一次。
- 持久化：`snapshot()` 只导出 `persist` 属性的裸值；`restore()` 回写。

**信号**：`on_value_changed(attribute_id, old, new)`、`on_source_applied(source_id)`、`on_source_removed(source_id)`。

### 5.9 `EvaluationPlan`（求值计划）

**存**：`definitions`、`order`、`index_of`、`depends_on`、`dependents_of`、`errors`。

**做**：`compile()` 建图、Kahn 拓扑排序、环检测，并生成稳定的求值顺序与反向边
（`dependents_of` 供脏传播使用）。
可选依赖缺失会被忽略；必需依赖缺失与自依赖会记入 `errors`；
成环的属性会退到队尾并记为错误。

**性质**：只读、无运行时状态，同一套定义编译一次即可被多张表共享。

### 5.10 `AttributeEvaluator`（求值器）

**存**：`plan`、已报告错误的属性集合。

**做**：

- `value_of(slots, revision, id)`：惰性取值，只有 `slot.is_dirty()` 时才重算，并递归处理依赖。
- `refresh_dirty(...)`：只刷新给定的脏属性集合。
- `refresh(...)` / `refresh_all(...)`：强制刷新单个属性或按计划整体刷新。
- `_aggregate(...)`：把修改器按桶聚合。

**防环**：计算开始前先把 `computed_revision` 标为当前版本，若仍有环，递归读取会拿到上一轮缓存而不是无限递归。

### 5.11 `AttributeSystem`（门面节点）

**存**：`attribute_set`（检查器装配）、`plan`、`evaluator`、`sheet`、`auto_refresh`。

**做**：

- 加载期准备一次：从 `AttributeSet` 取得共享计划，建立本实体的表。
- `validate_configuration()`：校验定义、依赖与环，不创建运行时状态。
- `_get_configuration_warnings()`：编辑器里直接显示配置问题。
- 属性访问：`get_value()`、`get_base_value()`、`set_base_value()`、`has_attribute()`。
- 来源管理：`apply_source()`、`remove_source()`、`set_source_stack()`、`set_modifier_value()`、`tick()`。
- 事务与存档：`begin_batch()` / `end_batch()` / `snapshot()` / `restore()`。
- 调试：`dump()` 打印本实体现场，`describe_plan()` 打印求值计划。
- 事件：把本实体表的事件向上转发（`on_attribute_changed` 等）。

**边界**：不做计算、不遍历依赖图、不持有其它实体的状态。

**惰性初始化**：任何接口在 `_ready()` 之前被调用时，`_ensure_ready()` 会自动完成编译与建表。

**编辑器支持**：脚本带 `@tool`，编辑器中 `_ready()` 直接返回，只执行配置校验；
属性定义可以在检查器里自由装配，保存后重新运行即可生效。

### 5.12 `AttributeSet`（配置集）

**存**：`definitions: Array[AttributeDefinition]`；运行时缓存 `_plan` 与 `_evaluator`（不序列化）。

**做**：

- `get_plan()`：首次调用时编译并缓存 `EvaluationPlan`，之后直接复用。
- `get_evaluator()`：返回与计划绑定的共享求值器（无实体状态）。
- `invalidate()`：清空缓存，下次重新编译。
- `validate()`：编译一份临时计划并返回错误，不写入缓存（编辑器校验用）。
- `has_definition()` / `get_definition()` / `get_definition_ids()`：定义查询。

**缓存规则**：所有引用同一份 `AttributeSet` 的实体共享同一个计划与求值器；
编辑器里不缓存，保证校验始终基于最新配置。

**边界**：只描述"有哪些属性"，不保存任何实体的裸值、来源或缓存。

---

## 6. 数据流与生命周期

### 启动

```
检查器装配 AttributeSystem.attribute_set
  -> 运行时 _ready() 调用 AttributeSet.get_plan()
  -> 首次使用时编译 EvaluationPlan（拓扑排序 + 环检测）并缓存
  -> 取得共享的 AttributeEvaluator
  -> 创建本实体唯一的 AttributeSheet（先算一遍初始值）
```

### 施加持续效果

```
ModifierSource
  -> sheet.apply_source()
  -> 深拷贝并记录来源
  -> 修改器入账到各 AttributeSlot
  -> revision += 1
  -> 按计划顺序重算
  -> 有变化的属性发 on_value_changed
```

### 施加即时效果

```
source.instant = true
  -> 直接写入 slot.base_value
  -> 不保留来源记录
  -> revision += 1，下游照常重算
```

### 限时效果

```
sheet.tick(delta)
  -> 推进 remaining_time
  -> 到期来源整体撤销（内部按批量处理）
```

### 配置校验（编辑器）

```
检查器修改 AttributeSet.definitions
  -> _get_configuration_warnings()
  -> validate_configuration()
  -> 空定义 / 重复 id / 缺失依赖 / 成环 直接显示为节点警告
```

### 存档

`snapshot()` 只保存 `persist = true` 属性的 `base_value`。
派生属性、缓存和事件都不入档，它们可以由定义与来源推导出来。

---

## 7. 扩展点

1. **统一的钳制 / 取整策略资源**：目前是 `AttributeDefinition` 的内联字段，若需要复用可抽成独立 `Resource`。
2. **跨属性钳制**：例如"当前生命值 ≤ 最大生命值"，可作为一条只读依赖参与计算。
3. **修改器优先级**：桶内目前按入账顺序处理；需要同桶 `OVERRIDE` 竞争时，可给 `AttributeModifier` 增加 `priority`。
4. **来源模板资源化**：`ModifierSource` 目前是运行时 `RefCounted`；若装备表要放进 `.tres`，可增加一层模板资源。
5. **来源持久化**：`snapshot()` 目前只存裸值；若 buff 需要跨存档，可同时导出活跃来源的 id 与层数。
6. **分组并行**：互不依赖的脏属性可以按求值计划分组并行计算（当前为单线程顺序求值）。

---

## 8. 约束与注意事项

- `AttributeDefinition.id` 必须非空且唯一；属性依赖只认 id。
- 依赖不能成环；`EvaluationPlan.compile()` 会在加载期报告。
- 派生贡献不写回 `base_value`。
- 运行期不再增删属性定义；需要修改时改资源并重新加载场景或游戏。
- 求值计划按 `AttributeSet` 缓存；所有引用同一份配置集的实体共享同一个计划。
- 每个实体只应挂一个 `AttributeSystem`，它只管理自己的 `AttributeSheet`。
- 定义资源可以跨实体共享，运行时状态不可以。
