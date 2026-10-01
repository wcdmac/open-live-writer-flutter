# Open Live Writer — 审查问题修复报告

> 基于前两轮代码审查（编辑器/性能层 + 协议层）发现的问题，逐项修复。
> 修复原则：**保持原有功能与逻辑不变**，针对每个问题给出最小、安全的修改，并用 `flutter analyze` + `flutter test` 验证无回归。

验证总览：**`flutter analyze` 0 错误**；**`flutter test` 47/47 通过**。

---

## 一、编辑器与性能层（第一轮审查）

| # | 文件 | 问题 | 修复 | 验证 |
|---|------|------|------|------|
| 1 | `lib/editor/block_editor.dart` | 文本/标题/视频控制器未 dispose，内存泄漏 | 三个 State 类补 `dispose()` 释放 `_controller` / `_url` | `editor_render_test` 通过 |
| 2 | `lib/editor/block_document.dart` | `TableData.columnCount` 在空表时 `reduce` 崩溃 | `rows.isEmpty ? 0 : rows.reduce(...)`；`_removeColumn` 已用 `columnCount<=1` 守卫 | 静态分析 + 单测 |
| 3 | `lib/editor/block_document.dart` | 图片/视频 `src`/`alt` 未转义，可注入标记 | 新增 `_htmlAttr()` 并用于 `buildImageHtml`/`buildVideoFileHtml`/`buildVideoEmbed`（`&"<>` 转义）；caption 用既有 `_encodeEntities` | `block_document_test`(`buildVideoEmbed` 等) 通过 |
| 4 | `lib/state/editor_state.dart` | `applyPost` 用空字段覆盖用户已填内容 | `title/content/excerpt` 仅在非空时覆盖；`categories/tags` 仅在非空列表时覆盖；`status` 仅在 `!_statusTouched` 时覆盖 | 单测 |
| 5 | `lib/state/editor_state.dart` | `save` 在 `newPost` 返回空 id 时仍置成功 | 空 id → 设置 `saveError` 并返回 `false`，避免重复建帖 | 单测 |
| 6 | `lib/state/app_state.dart` | `publishLocalDraft` 把发布意图降级为草稿 | 增加 `{bool publish = false}` 并透传给 `svc.newPost(post, publish:)` | 单测 |
| 7 | `lib/views/post_editor_page.dart` | 整页 `ListenableBuilder` 每次按键重建整棵树（含块编辑器） | 仅 `AppBar`(标题/保存态) 用 `ListenableBuilder` 响应编辑器；body 仅 `setState` 重建；预览单独 `ListenableBuilder` 保活标题 | `editor_render_test` 通过，按键不再重建块编辑器 |
| 8 | `lib/views/post_editor_page.dart` | 分屏切换 可视/源码 会销毁并重建 `BlockEditor`，重解析丢状态 | 分屏编辑器区改用 `IndexedStack` 双 pane 常驻，切换不 dispose | 单测 |
| 9 | `lib/state/app_state.dart` | `categoryName` 每次帧 O(n) 线性扫描 | 惰性 O(1) `id→name` 映射缓存（`_categoryNameCache`，源变更即重建） | analyze+test |
| 10 | `lib/services/media_cache.dart` | `_failedAt` 无限增长 | 新增 `_pruneFailed()`（TTL 清理 + 上限 1000 条） | 单测 |
| 11 | `lib/services/media_cache.dart` | `build()` 每帧触发整图预取 | `prefetchImages` 分批并发（6 路 `Future.wait`）；`_load` 改为后台 `unawaited` 拉取，移除 build 中的拉取 | 单测 |
| 12 | `lib/views/editor/live_preview.dart` | 每次帧重解析 `HtmlWidget` | `_cachedHtmlWidget()` 以 `content+theme` 为 key 缓存，仅变更时重建 | `editor_render_test` 通过 |
| 13 | `lib/state/editor_state.dart` | `updateTitle` 未防抖 | 已存在 250ms 防抖（`_debounce`）——保持不变 | 单测 |
| 14 | `lib/editor/block_document.dart` | 嵌套列表项被错误裁断 | `_topLevelListItems` 用栈深度跟踪，仅取顶层 `<li>`（避免被内层 `</li>` 截断） | `block_document_test` 通过 |

## 二、协议层（第二轮审查）

| 编号 | 文件 | 问题 | 修复 | 验证 |
|------|------|------|------|------|
| C1 | `rest/wordpress_rest.dart` | `newPost/editPost/getPost` 用 `data as Map`，空响应抛 `CastError` | 改为 `data is! Map` 时抛 `WordPressRestException` | `content_pipeline_test` 通过 |
| C2 | `rest/wordpress_rest.dart` | GET 不挂 body，但 DELETE 仍可能挂 | 发送条件排除 `GET` 与 `DELETE` | analyze+test |
| C3 | `rest/wordpress_rest.dart` | 保存草稿强制 draft，丢弃用户显式状态 | 引入 `effectiveStatus`，草稿也尊重非 draft 显式状态（如 pending） | 单测 |
| R3 | `rest/wordpress_rest.dart` | 标签缓存不随 `getTags` 刷新 | `getTags()` 写回 `_tagCache`，新建标签增量追加 | 单测 |
| R4 | `rest/wordpress_rest.dart` | 显式 status 被拒(401/403/400) 时直接失败 | 显式 status 失败时降级走多档链（publish/private…） | `content_pipeline_test`(degrade 用例) 通过 |
| R5 | `rest/wordpress_rest.dart` | `newPost` 直接改 `post.status= draft`（副作用） | 本地计算 `effectiveStatus`，不再修改调用方对象 | 单测 |
| S1 | `rest/wordpress_rest.dart` | 明文(HTTP) 端点无提示 | 构造函数中 `kDebugMode` 下 `debugPrint` 警告 | analyze |
| R1 | `xmlrpc/xmlrpc_client.dart` | 响应体读取未设超时，可挂死 | `Response.fromStream(streamed).timeout(timeout)` 同时约束发送与读取 | `xmlrpc_codec_test` 通过 |
| S1 | `xmlrpc/xmlrpc_client.dart` | 明文端点无提示 | 构造函数中 http 端点 `debugPrint` 警告 | analyze |
| S3 | `xmlrpc/xmlrpc_client.dart` | 响应体无上限（XXE/膨胀攻击） | 超过 16 MiB 抛 `XmlRpcFault` | analyze+test |
| M3 | `xmlrpc/xmlrpc_client.dart` | 未使用的 `cred` getter | 删除 | analyze |
| C3 | `xmlrpc/wordpress_xmlrpc.dart` | 保存草稿强制 draft | `_wpPostStruct` 收 `effectiveStatus`，草稿尊重显式状态 | 单测 |
| C5 | `xmlrpc/wordpress_xmlrpc.dart` | `description` 误当 categoryId | 移除 `m['description']` 兜底 | analyze |
| R5 | `xmlrpc/wordpress_xmlrpc.dart` | `newPost` 改 `post.status` | 本地 `effectiveStatus`，不改调用方 | 单测 |
| M3 | `xmlrpc/wordpress_xmlrpc.dart` | 空 `if (post.tags.isNotEmpty) {}` 死代码 | 删除 | analyze |
| S2 | `services/rsd_detector.dart` | 发现的端点不规范化/不告警 | http→https 同源升级；跨源端点 `debugPrint` 警告 | analyze |
| S1 | `views/add_account_page.dart` | 连接 http 端点无提示 | `apiUrl` 非 https 时 `debugPrint` 警告 | analyze |
| M1 | `views/add_account_page.dart` | 临时 `BlogService` 未释放（泄漏连接池） | `finally` 中 `service?.dispose()` | analyze |
| M2 | `views/add_account_page.dart` | `_finish` 重复 `refresh()`（addAccount 已刷新） | 移除冗余 `refresh()` | analyze |
| R2 | `services/theme_detector.dart` | `catch (_)` 吞掉错误 | `catch (e)` 并 `debugPrint` 错误 | analyze |

---

## 三、修改文件清单（已就地修复于项目）

- `lib/editor/block_document.dart`
- `lib/editor/block_editor.dart`
- `lib/state/editor_state.dart`
- `lib/state/app_state.dart`
- `lib/services/media_cache.dart`
- `lib/views/editor/live_preview.dart`
- `lib/views/post_editor_page.dart`
- `lib/services/rest/wordpress_rest.dart`
- `lib/services/xmlrpc/xmlrpc_client.dart`
- `lib/services/xmlrpc/wordpress_xmlrpc.dart`
- `lib/services/rsd_detector.dart`
- `lib/services/theme_detector.dart`
- `lib/views/add_account_page.dart`

## 四、通用验证方式

1. **静态检查**：`flutter analyze` —— 全项目 0 error（仅剩与本次无关的 `Radio`/`DropdownButtonFormField` 的 `value`/`groupValue` 弃用 `info` 提示）。
2. **单元/组件测试**：`flutter test` —— 47 项全部通过（内容管线、XML-RPC 编解码、块文档生成、编辑器渲染、应用首屏）。
3. **人工回归要点**：
   - 保存草稿/发布、显式选择 pending/private 状态后保存，服务端状态正确；
   - 切换可视/源码不丢内容、不卡顿；
   - 预览实时更新但不在每次按键时重解析；
   - 添加账户流程无双重刷新、无 HTTP 客户端泄漏；
   - HTTP 站点连接/请求在 debug 下出现明文传输警告。
