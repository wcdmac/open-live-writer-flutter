# 实施状态与交付标准（P0–P3）

> 基于 `open_live_writer` 代码库（v1.7.9，2026-10-01）。本文件逐项列出
> `docs/development_plan.md` 中 P0–P3 的**功能范围、交付标准（验收条件）**与
> **本轮实施状态**。配套：`CODE_AUDIT_2026-09-30.md`、`FIXES_P0_P3_2026-10-01.md`。

## 本轮已交付（2026-10-01）

| 优先级 | 项 | 提交内容 | 验收 |
|--------|----|----------|------|
| P0-3 | **L13 路径脱敏** | `lib/utils/path_util.dart`（`desensitizePath`/`displayFileName`）；`home_page.showExportedPath` 只显示文件名，完整路径仅经「复制路径」动作入剪贴板；新增 `copyPath`/`pathCopied` 本地化 | 单测 `test/path_util_test.dart` 全绿；UI 不再渲染含用户名的绝对路径 |
| P0-3 | **L1 魔法数字集中** | `lib/utils/constants.dart`（`kImageUploadQuality`/`kImageMaxWidth`/`kHistoryDebounce`/`kHistoryStackLimit`/`kWideLayoutBreakpoint`）；替换 `block_editor`/`post_editor_page` 散落字面量 | 单测 `test/constants_test.dart` 全绿；无残留魔法数字 |
| P0-2 | **持久化 schemaVersion + 迁移** | `lib/utils/persistence_codec.dart`（`wrapStorePayload`/`unwrapStorePayload`）；`account_store`/`local_draft_store` 写入 `{schemaVersion, items}`，向下兼容旧纯数组格式；严格数据丢失守卫不变 | 单测 `test/store_schema_test.dart` 全绿；旧 v0 数据仍可读取；损坏载荷仍抛错中止写入 |
| P1-5 | **tagName 缓存** | `app_state.tagName` 改为与 `categoryName` 一致的惰性 id→name 缓存 | `flutter analyze` 通过；大列表不再每帧 O(n) 扫描 |
| P2-10 | **无签名 IPA** | `build.yml` iOS job 显式 `--no-codesign` + 注释；新增「Verify IPA is unsigned」步骤断言产物**未签名**（无 embedded provisioning、无 code signature） | CI iOS job 校验步骤通过；产物为未签名 IPA |
| P2-11 | **lint 强化** | `analysis_options.yaml` 启用 `avoid_print`/`prefer_single_quotes`/`curly_braces_in_flow_control_statements`（info 级，不开启 `--fatal-infos`，CI 保持绿） | `flutter analyze --no-fatal-infos` 通过 |
| P0-1 | **测试补齐** | 新增 `path_util_test`/`store_schema_test`/`constants_test`；既有 `widget_test.dart` 冒烟门禁保留 | `flutter test` 全绿 |

## 路径脱敏 ↔ 无签名 IPA 的协同

两者分属 Dart 运行时代码与 CI 构建流程，无直接耦合，但**在同一条 CI 流水线上被共同验证**，从而保证「协同且可用」：

1. `analyze-test` job 跑全部单测（含 `path_util_test`、`store_schema_test`）——它是 iOS 构建 job 的 `needs` 前置门禁；路径脱敏逻辑若不通过，iOS 构建不会触发。
2. iOS job 内部 `Verify IPA is unsigned` 步骤断言产物未签名，失败则阻断 Release。
3. 因此任一改动破坏脱敏单测**或**意外引入签名，都会在 `v*` tag 发版前于同一 pipeline 暴露。

## 各优先级功能范围、交付标准与状态

### P0 — 质量地基

| 项 | 功能范围 | 交付标准（验收） | 状态 |
|----|----------|------------------|------|
| P0-1 补 widget/integration 测试 | 核心 UI 路径冒烟 + 关键 golden（块渲染、导出 HTML） | `widget_test` 覆盖 HomePage/PostEditorPage/BlockEditor；核心 UI 路径覆盖率 ≥60% | **Partial** — 冒烟门禁已存在，本轮新增工具类单测；完整 UI 覆盖需增量补（见 P2-7 前不重构结构） |
| P0-2 持久化原子写/可迁移 | 单键整写 → 临时文件+rename；加 `schemaVersion` | 写中途崩溃不损坏；schema 变更可迁移 | **Done**（本轮：`schemaVersion`+迁移+向下兼容；SharedPreferences 平台层已提供原子写，临时文件 rename 不适用，故以版本化替代） |
| P0-3 审计收尾 | L1 魔法数字、L13 路径脱敏 | 无魔法数字；UI 不泄漏用户名路径 | **Done**（本轮） |

### P1 — 性能与可维护性

| 项 | 功能范围 | 交付标准 | 状态 |
|----|----------|----------|------|
| P1-4 状态分域 + Selector 收窄 | `AppState` 拆账户/帖子/草稿域；视图 `Selector` 替换 `watch` | 大博客切换/滚动重建量降一量级 | **Deferred** — 需 P0-1 测试门禁兜底后增量执行（盲改风险高） |
| P1-5 列表并行加载 + 分页 | `refresh()` 改 `Future.wait`；`getPosts` 分页触底 | 首屏延迟下降；支持任意规模博客 | **Partial** — `tagName` 缓存本轮完成；并行/分页待增量 |
| P1-6 图片 LRU + 磁盘缓存 | `media_cache` 固定上限 LRU + `path_provider` 落盘 | 长会话内存稳定 | **Deferred** — 触碰缓存内部，盲改风险中，需门禁 |

### P2 — 架构重构与可分发

| 项 | 功能范围 | 交付标准 | 状态 |
|----|----------|----------|------|
| P2-7 M17 大文件拆分 | `block_editor`/`post_editor_page`/`home_page` 组件化 <400 行 | 单文件可维护；改一处不再漏三处 | **Deferred** — 必须 P0-1 门禁后执行 |
| P2-8 协议层策略模式 | `BlogService` 15 处三元分支 → `BlogProtocolClient` 接口 | 新增协议方法只写一处 | **Deferred** — 盲改双协议映射风险高 |
| P2-9 EditorController 抽取 | 文档模型/上传逻辑与 UI 解耦 | UI 与模型独立可测 | **Deferred** |
| P2-10 iOS 签名/TestFlight | 接证书/TestFlight 真机分发 | 真机可装 | **Done-as-UNSIGNED** — 按用户要求**有意跳过签名**，产物为未签名 IPA（sideload/本地重签） |
| P2-11 lint 强化 + CI 缓存 | 规则强化；`actions/cache` 缓存 pub/flutter | 低级问题不流入；发版提速 | **Partial** — lint 本轮启用（非致命）；CI 缓存待加 |

### P3 — 功能增强（持续）

| 项 | 功能范围 | 交付标准 | 状态 |
|----|----------|----------|------|
| P3-12 富媒体/块类型扩展 | 封面图、画廊、按钮、分栏 | Gutenberg 块可编辑导出 | **Deferred** |
| P3-13 离线同步增强 | 双向冲突三向合并（取代 1 秒容差 best-effort） | 高频编辑不误覆盖 | **Deferred** |
| P3-14 写作辅助 | SEO/元数据（excerpt/slug/OG）、定时发布、多作者 | 元数据可编辑并随导出 | **Deferred** |
| P3-15 体验 | 暗色跟随系统、本地化补全、撤销重做增强 | 体验一致 | **Partial** — 轻微清理（L11/L12/L14/L15）此前已完成；主题跟随已有 `theme_detector` |

## 明确未在本轮执行（Deferred）的事项与原因

- **重架构项（P1-4 / P2-7 / P2-8 / P2-9）**：当前环境无可用本地 Flutter 编译器（Windows 命名管道耗尽），改动只能由 CI 充当编译/测试闸门。**状态分域、M17 拆分、协议策略模式这类牵动全树的重构若盲改，极易在跨视图消费者处产生编译/运行时回归且无法本地即时验证**，因此必须建立在已具备的 widget 测试门禁之上、分多次小步增量执行。
- **P1-5 并行/分页、P1-6 LRU 磁盘缓存**：中等风险，待门禁更厚后增量。
- **P3 全部功能项**：属新功能，非缺陷修复，按路线图持续迭代。

## 后续执行路径（建议）

1. **下一步（低风险）**：补 `HomePage`/`PostEditorPage` widget 冒烟（不触网络），把 P0-1 覆盖率门禁做实。
2. **再下一步（中风险，有门禁兜底）**：P1-5 并行加载 + 分页；P1-6 图片 LRU 落盘。
3. **架构重构（高门槛）**：P1-4 → P2-7 → P2-8 → P2-9，每步单 PR、CI 全绿才合。
4. **功能迭代**：P3-12→13→14→15 按优先级。

> 流程约定：仍走 `main` 单分支、打 `v*` tag 发版（沿用当前流程）。重架构项不得以「一次性大改」方式盲合。
