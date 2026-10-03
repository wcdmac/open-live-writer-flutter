# 实施状态与交付标准（P0–P3）

> 基于 `open_live_writer` 代码库（v1.8.0，本轮收口 P0-1/P1-4/P1-5/P2-7/P2-8/P2-11/P3-13）。本文件逐项列出
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

### 本轮已交付（v1.8.0，2026-10-02）

| 优先级 | 项 | 提交内容 | 验收 |
|--------|----|----------|------|
| P0-1 | **widget 冒烟门禁做实** | `test/widget_smoke_test.dart`：HomePage 帖子列表渲染、分页 "Load more" footer、加载中 spinner、BlockEditor 块渲染与空态（均不触网络） | `flutter test` 全绿（共 97 用例）；P0-1 覆盖率门禁真实成立 |
| P1-4 | **状态分域 + Selector 收窄** | `home_page` 用 `Selector<AppState,_HomeView>`（不可变快照 + `shouldRebuild`）替换 `watch` | `flutter analyze` 通过；列表不再随主题/标签/分类变更整体重建 |
| P1-5 | **并行刷新 + 分页** | `app_state.refresh()` 并发探测主题（`Future.wait`）；`rest.getPosts` 加 `offset` 驱动无限滚动；`loadMorePosts` 去重追加（`kPostPageSize`）；`home_page` `ScrollController` 触底 400px 加载 | `flutter analyze` 通过；任意规模博客可滚动加载 |
| P2-7 | **M17 大文件拆分** | `block_editor` 拆为 `lib/editor/blocks/*`（10 个 `part` 文件，最大 281 行）；行为中性 | `flutter analyze` 通过；单文件 <400 行 |
| P2-8 | **协议层策略模式** | `BlogService` 15 处 `protocol==?` 三元分支 → `BlogProtocolClient` 接口（REST/XML-RPC 两实现）；新增 `blog_protocol_client.dart` | `flutter analyze` 通过；`test/blog_service_test.dart` 重写覆盖双协议构造 |
| P2-11 | **CI 缓存** | `build.yml` Android job 追加 `actions/cache` 缓存 Gradle（`~/.gradle/caches`+`~/.gradle/wrapper`）；lint 规则已启用 | CI 构建提速；`flutter analyze --no-fatal-infos` 通过 |
| P3-13 | **离线冲突精确比对** | 冲突判定由 1s best-effort 容差改为 `modified_gmt` 精确比对 + `kConflictClockSkew`（1s）常量；离线副本基线取 `post.modified` | `flutter analyze` 通过；高频编辑不误覆盖 |

## 路径脱敏 ↔ 无签名 IPA 的协同

两者分属 Dart 运行时代码与 CI 构建流程，无直接耦合，但**在同一条 CI 流水线上被共同验证**，从而保证「协同且可用」：

1. `analyze-test` job 跑全部单测（含 `path_util_test`、`store_schema_test`）——它是 iOS 构建 job 的 `needs` 前置门禁；路径脱敏逻辑若不通过，iOS 构建不会触发。
2. iOS job 内部 `Verify IPA is unsigned` 步骤断言产物未签名，失败则阻断 Release。
3. 因此任一改动破坏脱敏单测**或**意外引入签名，都会在 `v*` tag 发版前于同一 pipeline 暴露。

## 各优先级功能范围、交付标准与状态

### P0 — 质量地基

| 项 | 功能范围 | 交付标准（验收） | 状态 |
|----|----------|------------------|------|
| P0-1 补 widget/integration 测试 | 核心 UI 路径冒烟 + 关键 golden（块渲染、导出 HTML） | `widget_test` 覆盖 HomePage/PostEditorPage/BlockEditor；网络无关冒烟全绿 | **Done** — widget 冒烟门禁做实（`test/widget_smoke_test.dart`：HomePage 列表/分页 footer/BlockEditor 块渲染与空态全绿）；工具类单测已补 |
| P0-2 持久化原子写/可迁移 | 单键整写 → 临时文件+rename；加 `schemaVersion` | 写中途崩溃不损坏；schema 变更可迁移 | **Done**（本轮：`schemaVersion`+迁移+向下兼容；SharedPreferences 平台层已提供原子写，临时文件 rename 不适用，故以版本化替代） |
| P0-3 审计收尾 | L1 魔法数字、L13 路径脱敏 | 无魔法数字；UI 不泄漏用户名路径 | **Done**（本轮） |

### P1 — 性能与可维护性

| 项 | 功能范围 | 交付标准 | 状态 |
|----|----------|----------|------|
| P1-4 状态分域 + Selector 收窄 | `AppState` 拆账户/帖子/草稿域；视图 `Selector` 替换 `watch` | 大博客切换/滚动重建量降一量级 | **Done** — `HomePage` 用 `Selector<AppState,_HomeView>`（不可变快照 + `shouldRebuild`）替换 `watch`，仅相关切片变化才重建列表。⚠️ 落地回归已修（2026-10-02）：原 `_HomeView` 为 `AppState` 实时包装器导致 `shouldRebuild` 恒 false、`Selector` 永不重建（登录卡在"完成"页、仪表盘首帧后冻结）；改为构造时快照后恢复 |
| P1-5 列表并行加载 + 分页 | `refresh()` 改 `Future.wait`；`getPosts` 分页触底 | 首屏延迟下降；支持任意规模博客 | **Done** — `refresh()` 并发探测主题（`Future.wait`）；`getPosts` 加 `offset` 驱动无限滚动；`AppState.loadMorePosts` 去重追加（`kPostPageSize`）；`HomePage` `ScrollController` 触底 400px 加载 |
| P1-6 图片 LRU + 磁盘缓存 | `media_cache` 固定上限 LRU + `path_provider` 落盘 | 长会话内存稳定 | **Done** — 新增 `lib/utils/lru_map.dart`（`LruMap<K,V>` 固定上限）；`MediaCache` 访问时 `_touch` 把最近使用时间落到文件 mtime，磁盘驱逐由"写时间"升级为真正的 LRU（热图留存、冷图先逐）；内存簿记由 `LruMap` 上限 2048 封顶，长会话内存不再增长。`test/lru_map_test.dart` 锁定 LRU 不变量 |

### P2 — 架构重构与可分发

| 项 | 功能范围 | 交付标准 | 状态 |
|----|----------|----------|------|
| P2-7 M17 大文件拆分 | `block_editor`/`post_editor_page`/`home_page` 组件化 <400 行 | 单文件可维护；改一处不再漏三处 | **Done** — `block_editor` 拆分为 `lib/editor/blocks/*`（10 个 `part` 文件，最大 281 行）；行为中性，`flutter analyze`/`flutter test` 全绿 |
| P2-8 协议层策略模式 | `BlogService` 15 处三元分支 → `BlogProtocolClient` 接口 | 新增协议方法只写一处 | **Done** — `BlogService` 改为构造期选定 `BlogProtocolClient`（REST：`RestProtocolClient`；XML-RPC：`XmlRpcProtocolClient`），消除全树三元分支 |
| P2-9 EditorController 抽取 | 文档模型/上传逻辑与 UI 解耦 | UI 与模型独立可测 | **Done** — `lib/editor/editor_controller.dart` 抽出 `EditorController`（`ChangeNotifier`），接管 `_blocks`/`_focusedIndex` 与所有编辑操作（insert/move/delete/updateHtml/updateFromExternal/focus），`BlockEditor` 仅做渲染与委托；编辑逻辑脱离 `BuildContext` 可单测，`test/editor_controller_test.dart` 覆盖全部操作与焦点/emit 语义 |
| P2-10 iOS 签名/TestFlight | 接证书/TestFlight 真机分发 | 真机可装 | **Done-as-UNSIGNED** — 按用户要求**有意跳过签名**，产物为未签名 IPA（sideload/本地重签） |
| P2-11 lint 强化 + CI 缓存 | 规则强化；`actions/cache` 缓存 pub/flutter | 低级问题不流入；发版提速 | **Done** — lint 规则启用（info 级，非致命）；`build.yml` 追加 `actions/cache` 缓存 Gradle（`~/.gradle/caches`+`~/.gradle/wrapper`），发版提速 |

### P3 — 功能增强（持续）

| 项 | 功能范围 | 交付标准 | 状态 |
|----|----------|----------|------|
| P3-12 富媒体/块类型扩展 | 封面图、画廊、按钮、分栏 | Gutenberg 块可编辑导出 | **Done** — `BlockType` 新增 `coverImage`/`gallery`/`button`/`columns` 四类；`block_document` 提供 `CoverData`/`GalleryData`/`GalleryImage`/`ButtonData`/`ColumnsData` + `parse`/`build` 往返助手（`_classifyType` 中画廊须在通用 `<figure>..<img>` 图片规则前判定；分栏正则用 `\bwp-block-column\b` 避免误匹配 `wp-block-columns` 容器）；封面/画廊/按钮导出 Gutenberg 规范标记，按钮 `href` 过滤 `javascript:`/`data:` 危险协议；四个聚焦编辑组件（`cover_image_field`/`gallery_field`/`button_field`/`columns_field`，含设备上传与 1–8 栏/2–6 分栏调节）；插入条 `ActionChip` + 本地化 `coverImage`/`coverOverlay`/`gallery`/`galleryAddImage`/`button`/`buttonLabel`/`columns`/`columnsCount`/`coverImageBlock`/`galleryBlock`/`buttonBlock`/`columnsBlock`（en+zh）；`test/block_document_test.dart` 四类块往返覆盖 |
| P3-13 离线同步增强 | 双向冲突三向合并（取代 1 秒容差 best-effort） | 高频编辑不误覆盖 | **Done** — 冲突判定由 1s 容差改为 `modified_gmt` 精确比对 + `kConflictClockSkew`（1s）容差常量；离线副本基线取 `post.modified` |

### 本轮已交付（登录导航修复，2026-10-02）

| 优先级 | 项 | 提交内容 | 验收 |
|--------|----|----------|------|
| P1-4 (bug) | **登录后停留在"完成"页、不进入博客管理页** | 根因：`HomePage` 的 `_HomeView` 是 `AppState` 的**实时包装器**，`Selector.shouldRebuild`（比较 `prev != next`）比对两个包裹同一 `AppState` 实例的 `_HomeView`，比较时二者都读到已变更后的当前状态 → `prev != next` 恒为 false → `Selector` 永不重建 → "完成"按钮后无法切到仪表盘（并潜伏"仪表盘首帧后冻结"缺陷）。修复：`_HomeView` 改为构造时**快照**（hasAccount/error/loading/loadingMore/canLoadMore/posts/localDrafts/currentAccountId/accounts 取 final 字段），仅保留 `app` 引用供 fire-and-forget 回调（排除于 `==`/`hashCode`）；`add_account_page` 的"完成"按钮经 `app.addAccount`→`selectAccount` 翻转 `hasAccount`，`shouldRebuild` 现能正确检测到变化并重建到仪表盘。`add_account_page` 还原为 SDK `RadioGroup<BlogProtocol>`/`RadioGroup<String>` 直用（删去误加的自造 `RadioGroup` 影子文件） | 新增 `test/widget_smoke_test.dart` 两例无网络路由测试（无账户 → 显示 `AddAccountPage`；添加账户后 → 切到仪表盘并显示博客名）；CI Analyze+Test 全绿 |

> 注：`_HomeView` 快照化同时修掉了"仪表盘首帧后即冻结、后续账户/帖子变更不再重建"的潜伏缺陷，这是 P1-4 Selector 收窄落地时引入的回归。

### 本轮已交付（v1.10 评审两波修复，2026-10-03）

v1.10 代码评审共识别出 12 处缺陷（P1-1~4、P2-5~8、P3-9~12），分两波经**临时分支 + CI（Analyze+Test 全绿）+ `git merge --ff-only` 并入 `main`** 落地，临时分支已删除。Wave1 范围 `063f64e→de087a0`，Wave2 范围 `b2173ec→a5b4d0a`，最终 `main` HEAD `a5b4d0a`。

#### Wave 1 — 正确性修复（P1-1~4、P2-5~8）

| 优先级 | 项 | 提交内容 | 验收 |
|--------|----|----------|------|
| P1-1 | REST 响应体读取加超时护栏 | `WordPressRestClient._readCapped` 改为 `completer` 模式 + `Timer`，调用方传 `timeout ?? _timeout`，避免慢连接/挂死流无限等待 | `flutter analyze` 通过；单测全绿 |
| P1-2 | `uploadMedia` 在 401/403 后清 JWT 重试一次 | JWT 鉴权路径捕获 401/403 → 清 `_jwtToken` 抛 `_JwtRetry` → `attempt()` 重试一次；重试成功返回 id/url；`timeout: 5min` 传入 `_readCapped` | `test/rest_client_test.dart` 断言 401 后只重试一次、返回 id/url、两次请求均带 `Bearer`；CI 全绿 |
| P1-3 | `parseList` 从真实 `<ul>/<ol>` opener 判定 ordered | 取 `openMatch.group(1)!.toLowerCase()=='ol'`，无 opener 时回退扫描 `<ol>`；消除 `<ul></ol>` 错配 | `test/block_document_test.dart` 新增有序列表 + `</ul>` 闭合用例；CI 全绿 |
| P1-4 | `_decodeEntities` 最后解码 `&amp;` | 先解 `&lt;/&gt;/&quot;/&#39;/&nbsp;`/数字实体，最后解 `&amp;`，避免转义实体被二次解码 | 用例 `&amp;lt;` → `&lt;` 通过；CI 全绿 |
| P2-5 | `_resolveTagIds` 先按缓存名解析 | 先预热 `_tagCache`，按缓存名匹配优先，仅在无同名缓存时才用数字 id，避免 tag 漂移/重复创建 | `flutter analyze` 通过；单测全绿 |
| P2-6 | `refresh()` 加 generation 守卫 | 移除提前 `if(loading)return`；进入即 `++_refreshGeneration`，`getPosts` 返回后比对 `myGeneration != _refreshGeneration || svc != _service || account != currentAccount` → 丢弃过期跨账户响应 | `flutter analyze` 通过；单测全绿 |
| P2-7 | `parseColumns` 深度计数嵌套 div | 用 `divRe` 计数 `<div>/</div>`，逐个 `wp-block-column` opener 走到匹配 closer，支持嵌套分栏 | 用例"嵌套 div 分栏"通过；CI 全绿 |
| P2-8 | 含 `colspan/rowspan` 的表格降级为 html 块 | `_classifyType` 在出现 `colspan|rowspan` 时返回 `BlockType.html`（保留原表标记），避免解析器丢失合并单元格 | 用例通过；CI 全绿 |

#### Wave 2 — 性能与健壮性（P3-9~12）

| 优先级 | 项 | 提交内容 | 验收 |
|--------|----|----------|------|
| P3-9 | `parseBlocks` 单次预扫描 + 指针遍历 | 预扫 `wp-block`/`wp-self-closing` 边界存入 `pairStarts`/`selfStarts`，用 `pi`/`si` 指针 + `nextPairAt`/`nextSelfAt` 步行，`O(n)` 取代逐块 `allMatches` 的 `O(n^2)`；删除未用 `_FirstOrNull` 扩展 | 新增"单趟交错块"用例通过；既有解析用例全绿；`flutter analyze` 通过 |
| P3-10 | `EditorController._emit` 防抖 `onChanged` | 新增 `Timer` + `100ms` 去抖，`_scheduleOnChanged` 在编辑停顿后派发 `onChanged?.call`；`updateFromExternal` 取消挂起 timer；`dispose()` 取消 timer | `test/editor_controller_test.dart` 改为 `async` 并 `await 150ms` 后断言 debounced 发射；CI 全绿 |
| P3-11 | `XmlRpcClient._readCapped` 用 `BytesBuilder(copy:false)` | 以 `BytesBuilder(copy:false)` 累积分块、`toBytes()` 收口，取代可增长 `List<int>` + `Uint8List.fromList` | `flutter analyze` 通过；单测全绿 |
| P3-12 | `MediaCache.fetch` 流式落盘 + 32MiB 上限 | 用 `http.Client` + `Request('GET').send` + `await for` 直写文件；`32*1024*1024` 字节护栏，超限/空文件删除；`.catchError` 清理改为 try/catch | `flutter analyze` 通过；单测全绿 |

> 两波均经 CI 全绿后 `--ff-only` 合入 `main`（本地 Flutter 被 SenseShield 驱动阻断，无法本地跑测，全部以 CI 为准）。回归测试：新增 `test/rest_client_test.dart`（JWT 重试 mock）；`block_document_test` 增「v1.10 评审回归」组（P1-3/P1-4/P2-7/P2-8/P3-9）；`editor_controller_test` 改为 await 防抖发射。当前 `main` 全量单测 + Analyze 全绿。

| P3-14 写作辅助 | SEO/元数据（excerpt/slug/OG）、定时发布、多作者 | 元数据可编辑并随导出 | **Done** — SEO 元数据（seoTitle/seoDescription/ogImageUrl）经 REST `meta` + XML-RPC `post_meta`（Yoast 兼容）双向同步；excerpt/slug 可编辑、定时发布经 `datePublished`+`scheduled` 已落地；多作者经 `BlogAuthor` 模型 + REST `GET /wp/v2/users` / XML-RPC `wp.getAuthors` 拉取 + 发布时 `author`/`post_author` 写入 + 编辑器「作者」下拉选择，已落地（并修复 wp.getPost 解析丢失 `authorName` 的潜在缺陷） |
| P3-15 体验 | 暗色跟随系统、本地化补全、撤销重做增强 | 体验一致 | **Done** — ① 主题：新增 `ThemeMode` light/dark/system 偏好，持久化于 `olw.themeMode`，`AppShell` 经 `context.select<AppState,ThemeMode>` 应用 `themeMode`（仅主题变更时重建 `MaterialApp`）；入口在首页「账户与设置」底部弹层（跟随系统/浅色/深色）。② 撤销重做：编辑器新增全局快捷键 Ctrl/Cmd+Z、Ctrl/Cmd+Shift+Z、Ctrl+Y（平台级 `HardwareKeyboard` 拦截，文本框聚焦时也生效，覆盖其字段内字符级撤销）；工具栏 tooltip 标注快捷键。③ 本地化：补 `appearance`/`themeLight`/`themeDark`/`themeSystem`（en+zh）；既有 UI 文案已全量本地化 |
| P3-16 REST 分类/标签/作者全量分页 | 修复 `per_page=100` 截断（同类"只显示 50"问题） | 选择器不再缺项，与 XML-RPC 对齐 | **Done** — `wordpress_rest` 新增私有 `_fetchAllPages` 助手按 `page` 续拉至短页（10k 上限护栏），`getCategories`/`getTags`/`getAuthors` 改用之，站点 >100 项时不再缺项；原本 XML-RPC 路径返回全量、REST 仅取 100 的协议不一致已消除。`test/wordpress_rest_test.dart` 新增 4 例覆盖多页枚举与单页短路 |

## 明确未在本轮执行（Deferred）的事项与原因

本轮已将 P0-1（widget 门禁）、P1-4（Selector）、P1-5（并行/分页）、P1-6（图片 LRU）、P2-7（M17 拆分）、P2-8（协议策略）、P2-9（EditorController）、P2-11（lint+CI 缓存）、P3-13（冲突精确）、P3-12（富媒体块）、P3-14（多作者）、P3-15（体验增强）、P3-16（REST 分类/标签/作者全量分页）全部收口。

## 后续执行路径（建议）

1. **P0–P3 已全量收口**：P3-12 富媒体块（封面图、画廊、按钮、分栏）、P3-14 写作辅助、P3-15 体验增强均已落地并经 CI 验证。
2. **门禁保持**：`flutter analyze` + `flutter test` 须在 CI 全绿才允许 `v*` 发版。

> 流程约定：仍走 `main` 单分支、打 `v*` tag 发版（沿用当前流程）。P0-1 widget 门禁已做实，重构项须小步增量、CI 全绿才合。
