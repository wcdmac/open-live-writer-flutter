# Open Live Writer Flutter — 后续开发规划与优化方向

> 基于 `open_live_writer` 代码库实查（2026-10-01，v1.7.9）。所有定位均指向当前 `lib/` 实际文件。
> 配套文档：`docs/architecture.md`（契约）、`CODE_AUDIT_2026-09-30.md`（P0–P3 审查）、`FIXES_P0_P3_2026-10-01.md`（修复记录）。

---

## 0. 现状速览

| 维度 | 现状 |
|------|------|
| 规模 | 29 个 `.dart`，约 **13,676 行**；最大 `block_editor.dart` 1833 行、`post_editor_page.dart` 1408 行、`home_page.dart` 954 行 |
| 技术栈 | Flutter 3.11.5 / Dart 3.11；`provider`（ChangeNotifier）状态管理；`http`+`xml`+`html` 协议；`flutter_secure_storage`/`shared_preferences` 持久化；`flutter_widget_from_html_core` 渲染；`image_picker`/`share_plus`/`url_launcher`/`intl` |
| 架构 | Models / Protocol(REST + XML-RPC) / Facade(`BlogService`) / Persistence / State(`AppState`) / Editor / Views 分层清晰 |
| 质量基线 | CI 五平台构建 + Analyze&Test 全绿；协议/模型层测试 14 文件约 90+ 用例；**widget 层（BlockEditor/PostEditorPage/HomePage）0 覆盖** |
| 已知未做项 | M17 大文件拆分、L1 魔法数字集中、L13 导出路径脱敏（需产品决策） |

**一句话定位**：一个功能已较完整的跨平台 WordPress 编辑器，当前主要短板是**单体状态/超大 UI 文件带来的可维护性与大博客性能风险**，以及**测试覆盖不均衡**——这些是后续投入产出比最高的方向。

---

## 1. 架构设计优化

### 1.1 状态管理：拆分单体 `AppState`
- **问题**：`lib/state/app_state.dart`（432 行）一个 `ChangeNotifier` 持有账户、帖子、分类、标签、草稿、主题、错误，每次 `notifyListeners()` 广播全部监听者；大列表下重建范围过大。`categoryName()` 已加缓存（好），但 `tagName()`（`app_state.dart:423`）仍每次 `where` 线性扫描。
- **方向**：
  - 将 `AppState` 按域拆分为 `AccountState` / `PostListState` / `EditorState`（已有 `editor_state.dart`，可对齐）+ `DraftState`，各自 `ChangeNotifier`。
  - 视图侧用 `Selector` / `context.select` 收窄重建（仅帖子列表监听 `posts`，仅标题栏监听 `error`）。
  - `tagName` 改为与 `categoryName` 一致的惰性 id→name 缓存。
- **预期**：大博客仪表盘滚动/切换账户时 UI 重建量下降一个量级。

### 1.2 协议层：三元分支 → 策略模式
- **问题**：`lib/services/blog_service.dart` 中每个方法都用 `account.protocol == BlogProtocol.rest ? rest.x() : xmlrpc.x()` 三元路由（约 15 处），双协议实现散落两处，新增操作要改两遍。
- **方向**：定义 `BlogProtocolClient` 抽象接口，`RestClientImpl` / `XmlRpcClientImpl` 各自实现；`BlogService` 仅持有一个 `client`，消除分支。
- **预期**：新增协议方法（如媒体批量、评论）只写一处；双协议字段映射不一致（如 `modified` 仅 REST 有）集中收敛。

### 1.3 持久化：单键整写 → 原子写 + 可迁移
- **问题**：`account_store.dart` / `local_draft_store.dart` 把**整个数组写在一个 key** 下、整体重写（read-modify-write）。虽已加"解码失败即抛错"防静默丢失，但仍无原子性（写中途崩溃即损坏）、无 schema 版本/迁移（字段变更会读不出旧数据）。
- **方向**：
  - 短期：`write` 先落临时文件再 `rename`（原子替换），杜绝半写损坏。
  - 中期：引入 `drift`(SQLite) 或按账户/按草稿分文件（`path_provider` + JSON），带 `schemaVersion` 迁移。
- **预期**：数据损坏风险归零；大草稿量下读写从 O(全量) 降为 O(增量)。

### 1.4 编辑器：1833 行单体 → 组件 + Controller 分离
- **问题**：`block_editor.dart` 单文件含 10+ 内部 Widget（`_BlockCard`/`_TextBlockField`/`_ImageField`/`_VideoField`/`_ReadOnlyTable`/`_ReadOnlyCode`…），UI 与文档模型/上传逻辑耦合。
- **方向**：抽 `BlockEditorController` 持有 `BlockDocument` 与变更/历史；各 block 类型拆到 `lib/editor/blocks/`；toolbar 拆到 `lib/editor/toolbar/`。与 1.1 的 `EditorState` 对齐。
- **预期**：单文件降到 <400 行，改一个块类型不再牵动全局（即审计 M17）。

### 1.5 业务编排层
- 当前 `AppState` 方法（`refresh`/`publishLocalDraft`/`syncOfflineCopy`）既管状态又管协议编排。可引入轻量 use-case / coordinator，让 `AppState` 退化为纯状态容器。

---

## 2. 性能瓶颈分析与提升

| 瓶颈 | 位置 | 影响 | 方案 |
|------|------|------|------|
| 仪表盘串行加载 | `app_state.dart:162` `refresh()` 顺序 `getPosts→cats→tags→theme` | 首屏/切账户延迟叠加（跨境尤为明显） | `Future.wait` 并行分类/标签/主题；`getPosts` 先行出列表，其余后台补全 |
| 列表无分页 | `getPosts(count:50)` 写死 50 条 | 大博客（>50 篇）看不到旧文、内存随帖子增长 | 分页 / 无限滚动（ListView 触底加载下一页 `perPage`） |
| 重建范围过大 | `AppState` 全局 `notifyListeners` | 任意字段变化触发全树 rebuild | 见 1.1 Selector 收窄 |
| 图片内存缓存 O(n) 扫描 | `media_cache.dart:285` 累计写达阈值才全量扫描驱逐 | 长会话内存缓慢上涨 | 改 `LinkedHashMap` LRU 固定上限；大图磁盘缓存（`path_provider`） |
| 编辑器全文重渲 | `block_editor.dart` 长文 `setState` 全量 | 长文输入卡顿 | 文本块用 `TextEditingController` 直更；`const` 构造 + `itemExtent`；undo/redo 快照（100×2）改环形缓冲 |
| 启动串行 | `load()` 连接+刷新顺序 | 冷启动白屏偏长 | 账户恢复与首次刷新并行；骨架屏占位 |
| 构建慢 | CI 每次全量装依赖+五平台 | 发版 7–8 分钟 | `actions/cache` 缓存 `pub`/`flutter`；仅变更平台才重跑 |

---

## 3. 代码质量与可维护性改进

1. **大文件拆分（M17，已知未做）**：`block_editor` 1833 / `post_editor_page` 1408 / `home_page` 954 → 目标单文件 <400 行，组件化。**必须先补 widget 测试再动结构**（避免回归）。
2. **魔法数字集中（L1，未做）**：`2560`/`90`/`700ms`/`100 份快照`/`1000 宽屏断点` 等散落 → 命名为 `kHistoryLimit`、`kWideLayoutBreakpoint`、`kSnapshotDebounce` 等 `static const`。
3. **Lint 强化**：`analysis_options.yaml` 仅含 `flutter_lints` 默认。建议开启 `avoid_print`（仅保留 `kDebugMode` 处）、`prefer_single_quotes`、`curly_braces_in_flow_control_statements`；CI `analyze` 加 `--fatal-infos`。
4. **测试均衡**：
   - `test/editor_render_test.dart`、`test/widget_test.dart` 当前 **0 用例**（空壳）。
   - 补 `BlockEditor` / `PostEditorPage` / `HomePage` 的 widget + `integration_test` 冒烟；关键路径 golden test（块渲染、导出 HTML）。
   - 目标：核心 UI 路径覆盖率 ≥60%，回归门禁生效。
5. **日志统一**：散落 `debugPrint` 多处（可接受但无级别/无脱敏）。可抽 `lib/log.dart` 统一分级，敏感字段（密码、端点）一律不落日志。
6. **路径脱敏（L13，未做）**：导出成功提示展示含系统用户名的绝对路径（`home_page.dart:842`），仅显文件名、完整路径放"复制"动作——需产品确认。

---

## 4. 潜在技术债务梳理

| 债务 | 位置 | 风险 | 建议 |
|------|------|------|------|
| 单键整写持久化 | `account_store`/`local_draft_store` | 写中途崩溃损坏、无迁移 | 原子写→SQLite（见 1.3） |
| 超大 UI 文件 | `block_editor`/`post_editor_page`/`home_page` | 改动易漏、回归难测 | M17 拆分（见 1.4/3.1） |
| widget 层 0 测试 | 测试目录空壳 | 重构/功能回归无门禁 | 补 widget/integration（见 3.4） |
| 离线冲突仅 best-effort | `app_state.dart:370` 1 秒容差 | 高频编辑可能误判/误覆盖 | 改用 `modified_gmt` 精确比对 + 三向合并提示 |
| 双协议字段映射 | REST/XML-RPC 各一份 | 不一致（如 `modified` 仅 REST） | 策略模式统一（见 1.2） |
| iOS 未签名 ipa | CI `open-live-writer-ios-unsigned.ipa` | 真机需自签，分发门槛高 | CI 接证书/TestFlight 快发 |
| 无崩溃上报/遥测 | 仅 `debugPrint` | 用户侧故障不可见 | 接 Sentry/Firebase Crashlytics（仅 release） |
| 依赖版本偏旧 | `flutter_widget_from_html_core 0.17`、`xml 7`、`html 0.15` | 安全/兼容滞后 | 定期 `flutter pub outdated` 评估升级 |
| lint 宽松 | `analysis_options.yaml` | 低级问题流入 | 强化规则（见 3.3） |

---

## 5. 下一步功能迭代优先级、实施路径与预期收益

> 排序原则：先止血（质量/数据）/再流畅（性能）/后功能。每条给出"第一步动作"。

### P0 — 质量地基（1–2 周，阻塞后续重构）
1. **补 widget/integration 测试**（先测后改）
   - 路径：写 `test/widget/block_editor_test.dart`、`post_editor_page_test.dart`、`home_page_test.dart` 冒烟 + golden。
   - 收益：M17 拆分与状态重构有回归门禁，敢动结构。
2. **持久化原子写**（低风险高收益）
   - 路径：`local_draft_store`/`account_store` 的 `write` 改"临时文件 + rename"；加分 `schemaVersion`。
   - 收益：数据损坏风险归零。
3. **收尾审计未做项**：L1 魔法数字、L13 路径脱敏（产品确认后）。
   - 收益：代码一致性与隐私合规。

### P1 — 性能与可维护性（2–4 周）
4. **状态分域 + Selector 收窄**（1.1）+ **tagName 缓存**
   - 路径：拆 `AppState` 为账户/帖子/草稿三域；视图侧 `Selector` 替换 `watch`。
   - 收益：大博客切换/滚动流畅度显著提升，重建量降一量级。
5. **列表并行加载 + 分页**（2 表格）
   - 路径：`refresh()` 改 `Future.wait`；`getPosts` 加分页触底加载。
   - 收益：首屏与切账户延迟下降，支持任意规模博客。
6. **图片 LRU + 磁盘缓存**（2）
   - 路径：`media_cache` 改 LRU 上限 + `path_provider` 落盘。
   - 收益：长会话内存稳定，离线看图更快。

### P2 — 架构重构与可分发（1–2 月）
7. **M17 大文件拆分**（1.4）— 已有测试门禁后执行。
8. **协议层策略模式**（1.2）— 消除 15 处三元分支。
9. **编辑器 EditorController 抽取**（1.4）— UI 与模型解耦。
10. **iOS 签名/TestFlight 快发 + 崩溃上报** — 真机可分发的闭环。
11. **lint 强化 + CI 缓存**（3.3 / 2）— 质量与发版提速。

### P3 — 功能增强（持续）
12. **富媒体/块类型扩展**：封面图(featured image)、画廊、按钮、分栏等 Gutenberg 块；图片裁剪/批量上传。
13. **离线同步增强**：双向冲突三向合并（取代 1 秒容差 best-effort）。
14. **写作辅助**：SEO/元数据（excerpt、slug、OG）、定时发布 UI 完善、多作者/角色。
15. **体验**：暗色主题跟随系统（已有 `theme_detector`）、本地化补全、撤销重做增强。

### 优先级总表
| 优先级 | 项 | 周期 | 预期收益 |
|--------|----|------|----------|
| P0 | widget 测试 + 原子写 + 审计收尾 | 1–2 周 | 重构有门禁、数据零损坏 |
| P1 | 状态分域 + 列表分页并行 + 图片 LRU | 2–4 周 | 大博客流畅、内存稳 |
| P2 | M17 拆分 + 策略模式 + iOS 签名 + lint | 1–2 月 | 架构清晰、可真机分发 |
| P3 | 块类型/离线同步/SEO/体验 | 持续 | 功能广度与留存 |

---

## 6. 实施建议（落地顺序）
1. 本周：P0-1 起测试骨架（哪怕先 3 个冒烟用例），P0-2 原子写，**不碰结构**。
2. 下周：P0-3 收尾 + P1-4 状态分域（有测试兜底）。
3. 月度：P1-5/6 性能 + P2 重构（依赖 P0 测试门禁）。
4. 每个 PR 仍走 `main` 单分支、打 `v*` tag 发版（沿用当前流程）。
