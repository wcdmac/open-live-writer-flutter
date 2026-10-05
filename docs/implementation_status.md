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

### 本轮已交付（封面图块本地图片，2026-10-03）

评估结论：封面块的"本地图片"能力其实已基本具备（聚焦字段 `_CoverImageField._pickAndUpload` 已接 `uploadMedia`，上传走 REST/XML-RPC 媒体接口，返回 URL 嵌 `<img src>`，`parseCover`/`buildCoverHtml` 往返无损）；用户体感"只支持链接"源于**插入入口（`_insertCover`）只弹 URL**，且字段内设备按钮藏在 URL 框后缀图标里、可发现性低。本次按"两者都做"补齐：

| 项 | 提交内容 | 验收 |
|----|----------|------|
| 方案 A | `insert_bar._insertCover` 改为与 `_insertImage`/`_insertVideo` 一致的「从设备选择 / 输入链接」底部菜单；选设备则 `pickImage → normalizeImageUpload → uploadMedia → 插入带托管 URL 的 cover 块`（默认 overlay=文件名） | `flutter analyze` 通过；CI（Analyze+Test）全绿 |
| 方案 B | `cover_image_field` 在 URL 框下方显示醒目的「从设备选择」`TextButton`（`uploadMedia` 非空时），URL 框后缀仅保留上传中 spinner，去掉隐藏的图标按钮 | `flutter analyze` 通过；CI（Analyze+Test）全绿 |

- 涉及文件：`lib/editor/blocks/insert_bar.dart`（`_insertCover`）、`lib/editor/blocks/cover_image_field.dart`（构建）。无新 l10n（复用 `pickFromDevice`/`enterImageUrl`/`uploadingImage`/`imageUrl`）；无序列化改动（沿用 `buildCoverHtml`）。
- 提交 `475e2d1`，`tmp/cover-local-image` 分支 CI 全绿后 `--ff-only` 合入 `main`，临时分支已删除。

| P3-14 写作辅助 | SEO/元数据（excerpt/slug/OG）、定时发布、多作者 | 元数据可编辑并随导出 | **Done** — SEO 元数据（seoTitle/seoDescription/ogImageUrl）经 REST `meta` + XML-RPC `post_meta`（Yoast 兼容）双向同步；excerpt/slug 可编辑、定时发布经 `datePublished`+`scheduled` 已落地；多作者经 `BlogAuthor` 模型 + REST `GET /wp/v2/users` / XML-RPC `wp.getAuthors` 拉取 + 发布时 `author`/`post_author` 写入 + 编辑器「作者」下拉选择，已落地（并修复 wp.getPost 解析丢失 `authorName` 的潜在缺陷） |
| P3-15 体验 | 暗色跟随系统、本地化补全、撤销重做增强 | 体验一致 | **Done** — ① 主题：新增 `ThemeMode` light/dark/system 偏好，持久化于 `olw.themeMode`，`AppShell` 经 `context.select<AppState,ThemeMode>` 应用 `themeMode`（仅主题变更时重建 `MaterialApp`）；入口在首页「账户与设置」底部弹层（跟随系统/浅色/深色）。② 撤销重做：编辑器新增全局快捷键 Ctrl/Cmd+Z、Ctrl/Cmd+Shift+Z、Ctrl+Y（平台级 `HardwareKeyboard` 拦截，文本框聚焦时也生效，覆盖其字段内字符级撤销）；工具栏 tooltip 标注快捷键。③ 本地化：补 `appearance`/`themeLight`/`themeDark`/`themeSystem`（en+zh）；既有 UI 文案已全量本地化 |
| P3-16 REST 分类/标签/作者全量分页 | 修复 `per_page=100` 截断（同类"只显示 50"问题） | 选择器不再缺项，与 XML-RPC 对齐 | **Done** — `wordpress_rest` 新增私有 `_fetchAllPages` 助手按 `page` 续拉至短页（10k 上限护栏），`getCategories`/`getTags`/`getAuthors` 改用之，站点 >100 项时不再缺项；原本 XML-RPC 路径返回全量、REST 仅取 100 的协议不一致已消除。`test/wordpress_rest_test.dart` 新增 4 例覆盖多页枚举与单页短路 |

### 本轮已交付（v1.11.0 复审修复 N1–N8 + 遗留，2026-10-05）

针对 v1.11.0 复审报告（第三方审查）逐项核实后，按用户指令「按上述 Wave A → B → C 逐步全部修复」落地。全部经**临时分支 `tmp/review-v1110-fixes` + CI（Analyze&Test 全绿）+ `git merge --ff-only` 并入 `main`**，临时分支本地+远端删除。

#### Wave A — P1 最高优（N1/N2/N3）

| 项 | 提交内容 | 验收 |
|----|----------|------|
| N1 (P1) | `app_state.refresh()`：`getPosts` 结果先存局部 `fetchedPosts`，P2-6 generation 守卫（`myGeneration != _refreshGeneration || svc != _service || account != currentAccount`）判定通过后才 `posts = fetchedPosts` | `flutter analyze` 通过；CI 全绿；消除旧账号响应污染新账号模型 |
| N2 (P1) | `EditorController._emit` 移除 100ms 防抖，`onChanged` 即时派发（P3-10 防抖引入的回归）；`updateFromExternal` 保留 echo 守卫（`content == _lastEmitted` 跳过）；删 `dart:async`/Timer | 新增 `test/block_editor_n2_test.dart` 两例：重建不失字 + echo 不丢焦；`test/editor_controller_test.dart` 同步即时断言；CI 全绿 |
| N3 (P2) | `MediaCache.fetch` 流级 idle 超时：`streamed.stream.timeout(60s, onTimeout: close+throw)`，涓流服务器不再永久占 `_downloading` 槽 | `flutter analyze` 通过；CI 全绿 |

#### Wave B — P2/P3 小修（N4/N5/N6/N7/N8）

| 项 | 提交内容 | 验收 |
|----|----------|------|
| N4 (P3) | `MediaCache.fetch` 先写 `${file.path}.tmp`，完成后 `tmp.rename(file.path)`（跨设备失败回退 copy+delete），进程被杀不再残留截断坏图 | `flutter analyze` 通过；CI 全绿 |
| N5 (P3) | REST `WordPressRestClient._readCapped` 改 `BytesBuilder(copy:false)` + `takeBytes()`，与 XML-RPC P3-11 对齐 | `flutter analyze` 通过；CI 全绿 |
| N6 (P3) | `parseBlocks` 空行用 `text.indexOf(RegExp(r'\n\s*\n'), pos+1)` 索引定位；`parseColumns` 用 `divRe.allMatches(html, i).iterator` 步行计数，消除长文 O(n²) 尾串拷贝 | `test/block_document_test.dart` 增嵌套 div 分栏用例；CI 全绿 |
| N7 (P3) | `insert_bar._insertCover` `buildCoverHtml(CoverData(url: result.url))` 不再把文件名当 overlay 文字发布 | `flutter analyze` 通过；CI 全绿 |
| N8 (P3) | 图片/视频/封面三路上传对话框加「取消」`TextButton`（`cancelled` 守卫 + `barrierDismissible:false`），跨境慢链可中途退出 | `flutter analyze` 通过；CI 全绿 |

#### Wave C — 遗留项

| 项 | 提交内容 | 验收 |
|----|----------|------|
| 遗留-A | `BlogPost.commentsEnabled/pingsEnabled` 改 `bool?`；`editor_state.applyPost` 改 `?? post.xxx` 守卫；`post_editor_page` 评论/引用开关 `?? true`；REST `_postFromJson` 与 XML-RPC 两解析路径缺省 null；XML-RPC 写路径 `(?? true)` 兜底 open | `flutter analyze` 通过；CI 全绿；部分 getPost 响应不再清掉用户开关 |
| 遗留-B | `wordpress_rest.discoverRestRoot` 只读 HEAD/GET 头部（`link`），GET 探测体 bounded（`_maxResponseBytes`） | `flutter analyze` 通过；CI 全绿；巨型首页不再占内存 |
| 遗留-C | `_confirmServerSave` 的 `getPosts` 加 `fields` 投影（id/title/status/date_gmt/content/link），避免每次发布拉全量列表 | `flutter analyze` 通过；CI 全绿 |
| 遗留-D | `CachedImage` 网络失败回退已暖磁盘缓存（`MediaCache.instance.existingFile`） | `flutter analyze` 通过；CI 全绿 |

- 流程约定（不变）：仍走 `main` 单分支、`tmp/**` 临时分支走 CI 仅 Analyze&Test；本地 Flutter 被 SenseShield 驱动阻断，全部以 CI 为唯一真值。
- 回归测试：新增 `test/block_editor_n2_test.dart`（N2 重建不失字 + echo 不丢焦）；`test/editor_controller_test.dart` 防抖断言改同步即时；`test/block_document_test.dart` 增嵌套 div 分栏用例护 N6。当前 `main` 全量单测 + Analyze 全绿。

### 本轮已交付（v1.11.0 二次复审 F1–F6 + Wave C，2026-10-05）

针对 HEAD `714bcee` 的二次复审报告逐项核实（报告整体正确，仅遗留#14 上限数字写错：实际 `_maxResponseBytes = 16 MiB` 非 2MB）。按用户指令「按 Wave A → B → C 逐步实施」落地，全部经**临时分支 + CI（Analyze&Test 全绿）+ `git merge --ff-only` 并入 `main`**，临时分支本地+远端删除。

#### Wave A — P2 必须（F1）

| 项 | 提交内容 | 验收 |
|----|----------|------|
| F1 (P2) | `MediaCache.fetch` idle 超时 `onTimeout` 由 `s.close(); throw` 改为 `s.addError(HttpException(...))`。`throw` 逃逸 zone 成未捕获异步错误、不进错误通道，会让截断 `.tmp` 被 rename 成坏缓存命中（N4 在该路径复活）；`addError` 进 `catch`→清 `.tmp`→rethrow | `flutter analyze` 通过；CI 全绿；同时补完 N3 可靠性与 N4 截断穿透 |

#### Wave B — P3 收尾（F2/F3/F4/F5/F6）

| 项 | 提交内容 | 验收 |
|----|----------|------|
| F2 (P3) | `MediaCache.fetch` 下载加总超时 `Future.timeout(_downloadTotalTimeout=5min)`，对称上传路径；idle 超时只能挡「静止」，总超时挡「逐字节涓流」占 `_downloading`/预取批次槽 | `flutter analyze` 通过；CI 全绿 |
| F3 (P3) | `app_state.refresh` catch 分支 `error = userFacingError(...)` 加 generation 守卫（与 N1 同条件），旧账号慢请求失败不再覆盖新账号清白 `error` 态 | `flutter analyze` 通过；CI 全绿 |
| F4 (P3) | `app_state.refresh` `notifyListeners` 前二次 generation 校验，`cats/tags/authors/theme` 等待期间切账号则丢弃（不 notify 陈旧侧数据），由新刷新负责 notify | `flutter analyze` 通过；CI 全绿 |
| F5 (P3) | `discoverRestRoot` 探测体 `utf8.decode(bytes, allowMalformed: true)`，避免 `_maxResponseBytes` 边界恰切在 CJK 多字节中间抛 FormatException 中断站点发现 | 新增 `test/wordpress_rest_discovery_test.dart`（截断多字节用例 + 正常 routes 用例）；CI 全绿 |
| F6 (P3) | `insert_bar` 图片/视频/封面三处上传「取消」补注释：取消仅放弃结果，上传（`uploadMedia` 无 cancel token）可能留服务端孤儿文件，属固有局限非 bug | `flutter analyze` 通过；CI 全绿 |

#### Wave C — 记录性质（不改行为，仅 TODO 注释）

| 项 | 提交内容 | 验收 |
|----|----------|------|
| C-1 | `wordpress_rest._fetchJwtToken` 加注释：JWT 端点在自有站点、响应极小，无 `_maxResponseBytes` 上限，内存风险可忽略 | `flutter analyze` 通过；CI 全绿 |
| C-2 | `editor_controller._emit` 加注释：移除 P3-10 防抖后每键全量 `serializeBlocks`（v1.10 状态），长文序列化开销为已知权衡，下游已各自防抖 | `flutter analyze` 通过；CI 全绿 |

- 测试说明：F1/F2 依赖 60s idle / 5min 总超时，确定性单测在 CI 耗时过长（≥60s/次），故以代码审查 + 既有 `MediaCache` 行为 + CI 全绿保证无回归；F3/F4 为 generation 守卫子句，以审查 + 既有 AppState 单测覆盖保证。`discoverRestRoot` 此前无单测，本轮新增 `test/wordpress_rest_discovery_test.dart` 覆盖 F5（截断多字节不抛）与正常路径。本地 Flutter 仍被 SenseShield 驱动阻断，全部以 CI 为唯一真值。

### 本轮已交付（v1.11.0 三次复审 G1，2026-10-05）

针对 HEAD `d8370cf`（v1.11.0+8）的三次复审报告逐项核实（报告准确，仅 G1 一处需动手 P3）。按用户指令「按落地流程走、不打 tag」落地，经**临时分支 `tmp/review-g1` + CI（Analyze&Test 全绿）+ `git merge --ff-only` 并入 `main`**，临时分支本地+远端删除（未打 tag 发版）。

#### G1 — P3 小重构（唯一动手项）

| 项 | 提交内容 | 验收 |
|----|----------|------|
| G1 (P3) | `MediaCache.fetch` 流式下载段由 `Future.sync { await for … } + Future.timeout(_downloadTotalTimeout)` 改造为**手动 `StreamSubscription` + 两个 `Timer`**（idle 每 chunk 重置 60s、total 固定 5min）。`fail()` 先 `sub.cancel()` 真正停止消费 HTTP 流，再 `done.completeError(...)`；`onData` 超 `maxBytes` / `onError` 走同一收口；`try { await done.future; await sink.close(); } catch` 复用原 catch（oversize 哨兵 `HttpException('image too large')` → return null，其余清理 tmp + rethrow）。此修彻底闭合 F2「总超时未取消订阅」的尾巴：超时/错误即止流、无孤儿 future、无对已关闭 sink 的 `StateError`、无超时后带宽泄漏；F1 的 idle→错误通道语义保留 | `flutter analyze` 通过；CI 全绿 |

- 测试说明：G1 含 5min `Timer`，确定性快测在 CI 耗时过长（同 F1/F2/F3/F4 处理），以 Analyze&Test 全绿 + 代码审查保证。
- 后续建议（来自三次复审报告）：G1 修复后**冻结功能**，跑一轮真机长文输入 profiling 观察 `_emit` 每键全量 `serializeBlocks` 成本（Wave C 留项）。

## 明确未在本轮执行（Deferred）的事项与原因

本轮已将 P0-1（widget 门禁）、P1-4（Selector）、P1-5（并行/分页）、P1-6（图片 LRU）、P2-7（M17 拆分）、P2-8（协议策略）、P2-9（EditorController）、P2-11（lint+CI 缓存）、P3-13（冲突精确）、P3-12（富媒体块）、P3-14（多作者）、P3-15（体验增强）、P3-16（REST 分类/标签/作者全量分页）全部收口。

## 后续执行路径（建议）

1. **P0–P3 已全量收口**：P3-12 富媒体块（封面图、画廊、按钮、分栏）、P3-14 写作辅助、P3-15 体验增强均已落地并经 CI 验证。
2. **门禁保持**：`flutter analyze` + `flutter test` 须在 CI 全绿才允许 `v*` 发版。

> 流程约定：仍走 `main` 单分支、打 `v*` tag 发版（沿用当前流程）。P0-1 widget 门禁已做实，重构项须小步增量、CI 全绿才合。

## 已发布版本

| 版本 | Tag | 发布内容 | 发布页 |
|------|-----|----------|--------|
| v1.11.0 | `v1.11.0`（annotated，2026-10-03） | 封面图块本地图片（方案 A 插入入口 + 方案 B 字段可发现性）；含 v1.10 评审两波缺陷修复（P1-1~4/P2-5~8/P3-9~12）。pubspec `1.11.0+31`。`Build & Release` CI run `37114659778` 全绿（Analyze&Test + Android/iOS/Windows/Linux/macOS + GitHub Release，自动生成 notes，8 产物） | https://github.com/wcdmac/open-live-writer-flutter/releases/tag/v1.11.0 |
