# 全面代码审查报告（2026-09-30）

> 范围：`lib/` 27 个文件（约 10,500 行）+ `test/` 13 个文件（1,418 行）。
> 维度：① 逻辑/边界/异常 ② 性能/资源/重复计算 ③ 安全（输入校验/权限/敏感信息）④ 可维护性 ⑤ 测试与文档。
> 基线：`flutter analyze` → No issues found!；`flutter test` → 69/69 通过。
>
> 说明：静态分析绿灯 ≠ 无缺陷。下述问题多为**运行时语义、数据完整性与架构层面**问题，`analyze` 无法检出。
> 同类问题已归纳合并；凡标注行号者均经 Read 逐行核实。

---

## 一、严重（阻塞项：崩溃 / 数据丢失）

### S1. 异步后缺 `mounted` 检查 → `setState() after dispose()` 崩溃
- **位置**：`lib/editor/block_editor.dart:589`（`_ImageField._pickAndUpload`）、`:711`（`_VideoField._pickAndUpload`）
- **成因**：`await ImagePicker().pickImage/pickVideo(...)`（586/708）后仅判 `xfile == null`，**未判 `mounted`** 即 `setState`。系统相册会拉起外部 Activity，用户在此期间返回导致页面 pop，回调执行时 State 已 dispose。
  ```dart
  final xfile = await imgpick.ImagePicker().pickVideo(...);  // 708
  if (xfile == null) return;
  setState(() => _uploading = true);                        // 711 ← 缺 mounted
  ```
- **影响**：必现崩溃路径（返回手势 + 相册），未保存内容丢失。同类隐患见 `:1551`（`_insertImage` 第二个 `_prompt` 后直接 `onInsert`）。
- **修复**：每个 `await` 之后一律 `if (!mounted) return;`（586/708/1551 处）。

### S2. 视频整文件读入内存 → OOM
- **位置**：`lib/editor/block_editor.dart:713`
- **成因**：`await xfile.readAsBytes()` 一次性读入；`pickVideo` 未设 `maxDuration`，也无大小上限校验，视频无压缩（对比图片有 `maxWidth:2560, imageQuality:90`）。
- **影响**：数百 MB 视频直接触发 OOM 强退，长传中途崩溃。
- **修复**：上传前校验文件大小并提示；改走流式上传（`uploadMedia` 增加基于文件路径/Stream 的重载），或至少加 `maxDuration` 与大小上限。

### S3. 单条脏数据 → 全量账号/草稿被静默覆盖销毁（数据丢失）
- **位置**：`lib/services/account_store.dart:30-37`、`:111`；`lib/services/local_draft_store.dart:165-172`、`:175-185`
- **成因**：三处 `catch (_) { return []; }` / `return null` **静默吞掉解析失败**，返回空列表。而 `saveDraft`/`addAccount` 是**读-改-写**：以 `loadDrafts()` 的结果为基底追加后整体回写。
  ```dart
  // local_draft_store.dart:175
  final drafts = await loadDrafts(...);   // 解析失败 → 静默返回 []
  ...
  await setString(key, jsonEncode(drafts  // 只含这一条 → 其余草稿全被覆盖删除
  ```
  触发条件极低门槛：一条记录字段类型异常、JSON 被外部篡改、SharedPreferences 写入中断。
- **影响**：**静默、不可逆的用户数据全量丢失**，且无任何日志/告警，用户只看到"草稿不见了"。
- **修复**：① 解析失败时**不得返回空**，改为抛出带原因的异常或保留原始字符串并备份；② 写入前校验"读到的条数 > 0 或 key 原本不存在"，否则拒绝覆盖并告警；③ `catch` 中 `debugPrint` 记录原始内容。

### S4. 无全局异常捕获 + `load()` 无错误处理
- **位置**：`lib/main.dart:7-10`；`lib/state/app_state.dart:46-64`
- **成因**：`main()` 未设置 `FlutterError.onError` / `PlatformDispatcher.instance.onError`；`AppState.load()` 内 `store.loadAccounts()`、`_connectCurrent()`、`refresh()` 均无 try/catch，异常作为未处理异步错误冒泡。
- **影响**：启动阶段任何 IO/解析异常直接导致灰屏，用户无提示、开发者无堆栈；`load()` 失败后 UI 停在空状态。
- **修复**：`main()` 中注册全局错误处理器（记录 + 展示兜底错误页）；`load()` 包裹 try/catch 并写入 `error` 字段 + `notifyListeners()`。

---

## 二、中等（安全 / 性能 / 逻辑）

### M1. 异常原文直接展示给用户（信息泄露）
- **位置**：`lib/state/app_state.dart:188`（`error = 'Sync failed: $e'`）、`:344`；`lib/views/home_page.dart:98/476/700/742/789/823`（`operationFailed('$e')`）；`lib/views/post_editor_page.dart:209`（`_loadError = '$e'`）
- **成因**：`'$e'` 未经分类映射直接进 UI。协议层异常（XML-RPC fault / REST error）常携带 endpoint、用户名、本地路径。
- **影响**：泄露博客地址、账号名、内部路径、协议细节。
- **修复**：定义错误分类枚举（网络/鉴权/服务端/本地）→ 本地化文案；原始错误仅在 `kDebugMode` 下 `debugPrint`。

### M2. 视频 URL 未校验协议（注入面）
- **位置**：`lib/editor/block_document.dart:332`（配合 `block_editor.dart:768-770` 直接采用用户输入）
- **成因**：`_htmlAttr(u)` 只转义引号，**不校验 scheme**；任意字符串可生成 `<iframe src="javascript:...">` / `data:...`。
- **影响**：非 http(s) 源进入文章内容；预览与站点侧构成注入面，且 WP 会判为无效内容。
- **修复**：插入前 `Uri.tryParse` 并校验 `scheme ∈ {http, https}`（可选 youtu.be/vimeo 白名单），非法则拒绝并提示。

### M3. 插入链接的 URL 未转义（与同文件其他构建器不一致）
- **位置**：`lib/views/editor/editor_toolbar.dart:80` `_wrapSelection('<a href="$url">', '</a>')`
- **成因**：`url` 来自用户输入对话框，未调用转义。而 `block_document.dart:260` 的 `buildImageHtml` **已用 `_htmlAttr` 正确转义**——策略不一致。
- **影响**：URL 含 `"` 即可闭合属性注入任意 HTML，破坏文章结构。
- **修复**：改用 `_htmlAttr(url)`，并校验 scheme。

### M4. 文章密码明文输入
- **位置**：`lib/views/post_editor_page.dart:1218-1226`
- **成因**：`TextField` 未设 `obscureText: true`，未关闭 `enableSuggestions/autocorrect`。
- **影响**：肩窥泄露；密码进入输入法候选与建议缓存。
- **修复**：`obscureText: true` + `enableSuggestions: false` + `autocorrect: false`，增加显示/隐藏切换。

### M5. 击键级重复计算（长文卡顿）
- **位置**：`lib/views/post_editor_page.dart:294-304`（`_updateCharCount`：**每次调用编译 3 个 RegExp** + 全文档扫描，由两个 controller 的 listener 同步触发）；`lib/editor/block_editor.dart:304-316`（`_paragraphInner`/`_wrapParagraph` 每次调用新建 RegExp，其中 `_paragraphInner` 在 build 中被调用 `:265`）；`:63-66`（每次击键 `serializeBlocks` 全文档）
- **影响**：数百块的长文下每次击键 O(n) 多次 + 正则反复编译，输入明显卡顿。
- **修复**：正则提升为 `static final` 顶层常量；字数统计改增量或 debounce 300ms。

### M6. build 中做解析 + 逐字符触发网络请求
- **位置**：`lib/editor/block_editor.dart:799`（`_ReadOnlyTable` 内 `parseTable`，含 6 个 RegExp）、`:853`（`parseCodeBlock`）；配合 `lib/services/media_cache.dart:210-226`（`CachedImage.didUpdateWidget` 在 url 变化时立即 `fetch`）
- **成因**：图片 src 输入框每敲一个字符 → 父级重建 → `CachedImage` 收到新 url → 对**半截 URL** 发起一次下载。
- **影响**：表格/代码块每次卡片重建重解析（掉帧）；手输 URL 产生 N 次无效请求并污染磁盘缓存。
- **修复**：`_ReadOnlyTable`/`_ReadOnlyCode` 改为 `StatefulWidget`，在 `initState/didUpdateWidget` 解析并缓存；图片预览对 URL 做 `Uri.tryParse` + 300ms debounce 后再交给 `CachedImage`。

### M7. 整页重建范围过大
- **位置**：`lib/views/post_editor_page.dart:570` `context.watch<AppState>()`
- **成因**：AppState 任一 `notify`（刷新期间多次）重建整页，含两个 pane 的 `BlockEditor`、`EditorToolbar`、设置面板。
- **修复**：改 `context.read` + 用 `Selector<AppState, T>` 精确订阅所需字段。

### M8. MediaCache 驱逐策略 O(n²) 磁盘 IO
- **位置**：`lib/services/media_cache.dart:96`（`unawaited(_evictIfNeeded())`）、`:119-149`
- **成因**：**每次**下载完成后触发一次全目录 `list()` + 逐文件 `lastModified()`/`length()`。配合 `prefetchImages` 批量下载，N 张图触发 N 次全量扫描。
- **影响**：百图文章产生 O(n²) 次 stat 调用，磁盘 IO 抖动。
- **修复**：维护内存中的 size/LRU 账本，仅在累计写入超过阈值（如 16MB）时执行一次扫描；或改用文件系统队列异步驱逐。

### M9. 两个 TextField 共享同一 `TextEditingController`
- **位置**：`lib/views/post_editor_page.dart:825` 与 `:868`（均绑定 `_titleController`）
- **成因**：`IndexedStack` 会构建全部子节点，视觉 pane 与源码 pane 的标题框**同时**在树中。
- **影响**：两个 `EditableText` 争夺同一份 selection/composing 状态，切换 pane 时光标被另一字段改写，IME 输入跳字。
- **修复**：各自新建 controller 并双向同步，或改为单一标题框 + `ValueListenableBuilder` 镜像。

### M10. 关键操作静默失败
- **位置**：`lib/views/home_page.dart:669/711/731/752`
- **成因**：`svc == null || post.id == null` 时直接 `return`，无任何提示。
- **影响**：无连接时点击菜单"什么都没发生"，用户误以为成功。
- **修复**：统一 `_guard()`：失败时 `ScaffoldMessenger` 提示本地化错误。

### M11. 定时发布可调度到过去的时间
- **位置**：`lib/views/home_page.dart:671-688`
- **成因**：`firstDate: DateTime.now()` 但 `showTimePicker` 允许选择早于当前的时分，合成后为过去时间戳。
- **修复**：合成后校验 `date.isAfter(DateTime.now())`，否则提示重选。

### M12. 反序列化无守卫的强制转换（可触发 S3 数据丢失链）
- **位置**：`lib/models/blog.dart:132` `id: json['id'] as String`；`lib/services/local_draft_store.dart:86/87` `as String`
- **成因**：同一构造函数内其他字段均有 `?? 默认值` 兜底，唯 `id` 无守卫，风格不一致。
- **影响**：`id` 缺失/非 String → 抛异常 → 被 `loadAccounts`/`loadDrafts` 的 `catch` 吞掉 → 触发 **S3 全量丢失**。
- **修复**：统一改为 `as String? ?? ''` 并对空 id 跳过该条（保留其余数据）。

### M13. `AppState` 未重写 `dispose()` → HTTP 客户端泄漏
- **位置**：`lib/state/app_state.dart:16-44`（无 `dispose` 覆写）
- **成因**：`_service?.dispose()` 仅在 `_connectCurrent()` 切换账号时调用；AppState 本身销毁（热重启/Provider 卸载）时不释放 `BlogService` 持有的 `http.Client`。
- **修复**：覆写 `dispose()` → `_service?.dispose()`。

### M14. 离线副本同步无冲突检测（覆盖服务端修改）
- **位置**：`lib/state/app_state.dart:314-324` `syncOfflineCopy`
- **成因**：直接 `editPost` 覆盖，未比对 `LocalDraft.remoteModified` 与服务端 `modified_gmt`。
- **影响**：服务端在离线期间的改动被静默覆盖（last-write-wins）。
- **修复**：推送前 `getPost` 比对时间戳，冲突时提示用户选择保留版本。

### M15. XML-RPC 解码无递归深度限制
- **位置**：`lib/services/xmlrpc/xmlrpc_codec.dart:127-167` `_decodeValue`
- **成因**：对 `array`/`struct` 无深度上限递归；`XmlDocument.parse` 的 `XmlException` 与 `base64Decode` 的 `FormatException` 未转成 `XmlRpcFault`。
- **影响**：畸形/恶意深层嵌套响应可致栈溢出；异常类型不一致使上层难以统一处理。
- **修复**：增加深度参数（如上限 64）超限抛 `XmlRpcFault`；统一包装解析异常。

### M16. 崩溃恢复快照与用户输入竞态
- **位置**：`lib/views/post_editor_page.dart:495-543`
- **成因**：快照在 `addPostFrameCallback` 后异步读取，dialog 弹出前页面已可编辑；选择"恢复"会无条件覆盖标题/正文并 `_undoStack.clear()`。
- **影响**：dialog 出现前的输入被静默覆盖且无法撤销。
- **修复**：恢复前比对"当前内容是否仍等于打开时基线"，不一致则跳过或改为插入新草稿。

### M17. 重复代码块与超长方法（可维护性）
- **位置**：`lib/editor/block_editor.dart:977-1011` vs `:1145-1178`（`_ListField`/`_QuoteField` 的 `_syncCtrls`+`_wrapFocused` 近乎逐行重复）；`:1484-1558` vs `:1561-1632`（`_insertImage`/`_insertVideo` 同构）；`lib/views/post_editor_page.dart:990-1251`（设置面板 260 行）；`lib/views/home_page.dart:547-660`（`_showActions` 110 行）
- **影响**：修一处逻辑需同步改 2-3 处，极易漏改。
- **修复**：抽公共 `MultiLineItemField<T>`；媒体插入抽 `_pickOrUrlFlow()`；设置面板按维度拆 5 个私有 widget；`_showActions` 改数据驱动。

---

## 三、轻微（规范 / 一致性 / 覆盖）

| 编号 | 位置 | 问题 | 修复建议 |
|------|------|------|----------|
| L1 | `block_editor.dart:587/1514`、`post_editor_page.dart:232/241/430/572/1178` 等 | 魔法数字散落（2560、90、700ms、100 份快照、1000 宽屏断点…） | 集中为命名 `static const`（`kHistoryLimit`、`kWideLayoutBreakpoint`） |
| L2 | `app_state.dart:157/161/189/208/343` | 用 `print()` 而非 `debugPrint()`（Android 上会被丢弃/截断），与 `media_cache.dart:91` 的 `debugPrint` 风格不一致 | 统一 `debugPrint` + `kDebugMode` |
| L3 | `app_state.dart:254-259` | `publishLocalDraft` 的文档注释**整段重复两遍** | 删除重复段 |
| L4 | `app_state.dart:326-327` vs `:359-363` | `newDraftId()` 与 `newAccountId()` 实现重复且后者无分隔符（碰撞概率更高） | 抽统一 `generateId({prefix})` |
| L5 | `block_editor.dart:54` | `widget.content.trim() != _lastEmitted.trim()`：仅首尾空白不同则不重解析 → 显示陈旧内容 | 先判不等再 trim 比较，或引入显式 revision |
| L6 | `post_exporter.dart:51` `safeName` | 未处理 Windows 保留名（CON/PRN/AUX）与前导点 | 补保留名黑名单与 `trim('.')` |
| L7 | `post_exporter.dart:89` | 导出 HTML 的 `meta` 中 `authorName` 未 `_esc` 转义 | 套 `_esc()` |
| L8 | `post_exporter.dart:116/122` | Markdown front-matter 的 title/category/excerpt 仅转义 `"` 未转义换行 → YAML 断裂 | 转义 `\n` 或对多行值改用块标量 |
| L9 | `media_cache.dart:160` | `_pruneFailed()` 仅在 `prefetchImages` 中调用；单独走 `CachedImage` 预热时 `_failedAt` 可无界增长 | 在 `fetch()` 失败路径也做定期剪枝 |
| L10 | `blog.dart:34` | `XmlRpcFlavor.fromName` 用 `n.contains('wp')` 过度匹配（如含 "wpengine" 即判为 WordPress） | 改为精确值匹配或专用字段 |
| L11 | `home_page.dart:139-189` | `RefreshIndicator` 内 `ListView` 用默认 physics，条目不足时 Android 无法下拉刷新 | 显式 `AlwaysScrollableScrollPhysics()` |
| L12 | `home_page.dart:32-40` | `addPostFrameCallback` 内未判 `mounted` 即 `context.read` | 回调首行 `if (!mounted) return;` |
| L13 | `home_page.dart:842` | `SelectableText(path)` 展示含系统用户名的绝对路径 | 只展示文件名，完整路径仅在"复制"时提供 |
| L14 | `home_page.dart:196-198` | `async` 函数体内无 `await` | 去掉 `async` 或 `await` 结果 |
| L15 | `post_editor_page.dart:344` | `_save` 无并发兜底（仅靠 UI 隐藏按钮） | 增加 `if (_editor.saving) return;` |

### 测试与文档覆盖（维度⑤）
- **现状**：`test/` 共 13 文件 1,418 行。**协议层覆盖较好**（`wordpress_rest_test` 235 行、`content_pipeline_test` 336 行、`xmlrpc_codec_test` 186 行），但 **UI 层近乎零覆盖**：已核实无任何测试引用 `BlockEditor` 或 `HomePage`，仅 `editor_render_test`（86 行）涉及 `PostEditorPage`。
- **缺口**：撤销/重做与 100 份快照上限、块增删改序、表格行列增删、`_loadFullPost` 竞态、保存失败→落本地草稿、崩溃恢复、筛选与静默失败分支——**核心业务逻辑零回归保护**。
- **建议**：新增 `test/block_editor_test.dart`（块操作 round-trip）、`test/editor_history_test.dart`（undo/redo 上限）、`test/home_page_test.dart`（筛选 + 静默失败分支）、`test/post_editor_save_test.dart`（mock 网络失败 → 断言本地草稿落盘）。
- **文档**：`README.md` 存在；但数据模型（`BlogPost`/`LocalDraft` 的 offline-copy 语义）、`AppState` 的刷新重入规则、块编辑器 HTML 契约（哪些字段是 HTML 语义、哪些需转义）**缺少集中说明**，是 S3/M3 类问题的根源。建议补 `docs/architecture.md`。

---

## 四、分阶段优化规划

### 阶段 0：阻塞项（必须优先，建议 1–2 人日）
| 项 | 内容 | 优先级 | 工作量 | 预期收益 |
|----|------|--------|--------|----------|
| S1 | 补 `mounted` 检查（589/711/1551） | P0 | 0.5h | 消除必现崩溃路径 |
| S2 | 视频大小校验 / 流式上传 | P0 | 4h | 消除 OOM 强退 |
| S3 | 解析失败不再返回空 + 写入前防覆盖 + 日志 | P0 | 6h | **杜绝静默全量数据丢失** |
| S4 | 全局错误处理器 + `load()` try/catch | P0 | 3h | 灰屏可诊断、启动失败可提示 |
| M12 | `id` 等字段守卫（配合 S3） | P0 | 1h | 切断 S3 触发链 |

> **阶段 0 完成即可消除全部"用户可感知的崩溃与数据丢失"，是发布前的硬性门槛。**

### 阶段 1：短期重构（1 周内可完成）
| 项 | 内容 | 优先级 | 工作量 | 预期收益 |
|----|------|--------|--------|----------|
| M1 / M3 / M4 / M2 | 错误分类本地化、链接 URL 转义、密码 `obscureText`、视频 URL 协议校验 | P1 | 1 天 | 关闭 4 个安全面，消除信息泄露 |
| M5 / M6 | 正则静态化、字数统计 debounce、build 内解析外移、图片 URL debounce | P1 | 1.5 天 | 长文输入流畅度显著提升，无效请求归零 |
| M7 | `context.watch` → `Selector` | P1 | 0.5 天 | 刷新期掉帧消除 |
| M8 | MediaCache 驱逐改账本制 | P1 | 0.5 天 | 消除 O(n²) 磁盘 IO |
| M13 | `AppState.dispose()` | P1 | 0.5 天 | 关闭 HTTP 客户端泄漏 |
| M9 / M10 / M11 | 共享 controller、静默失败提示、定时发布时间校验 | P1 | 1 天 | 消除交互层正确性问题 |

### 阶段 2：中期架构与质量（2–4 周）
| 项 | 内容 | 优先级 | 工作量 | 预期收益 |
|----|------|--------|--------|----------|
| M17 | 块编辑器/设置面板/操作菜单拆分与去重 | P2 | 3–5 天 | 文件从 1747/1291 行降至可维护量级，改一处不再漏三处 |
| 测试补齐 | BlockEditor/HomePage/撤销栈/保存失败 4 个测试文件 | P2 | 4–6 天 | 核心逻辑回归保护从"≈0"提升到可安全重构 |
| M14 | 离线副本冲突检测 | P2 | 2 天 | 消除覆盖服务端修改 |
| M15 | XML-RPC 深度限制 + 异常统一 | P2 | 1 天 | 抗畸形响应 |
| M16 | 崩溃恢复竞态 | P2 | 1 天 | 消除输入被吞 |
| 文档 | `docs/architecture.md`（数据模型/刷新规则/HTML 转义契约） | P2 | 2 天 | 从根源减少 S3/M3 类"契约不明"缺陷 |
| L1–L15 | 常量集中、`debugPrint` 统一、注释去重等 | P3 | 2 天 | 代码一致性与可读性 |

### 优先级总览
```
P0 阻塞：S1 S2 S3 S4 M12        → 1–2 人日，必须先做（崩溃 + 数据丢失）
P1 短期：M1–M11（安全 4 项 + 性能 4 项 + 交互 3 项）→ ~1 周
P2 中期：M14–M17 + 测试补齐 + 文档 → 2–4 周
P3 收尾：L1–L15 规范清理        → 2 天
```

---

## 五、审查结论

当前代码**静态质量良好**（analyze 0 警告、69 项测试通过、协议层测试覆盖扎实），此前多轮修复已消除大部分中高危协议层缺陷。本次审查新增发现的问题集中在三个层面：

1. **数据完整性**（S3 + M12）——最严重，静默全量丢失且无告警，必须优先修复；
2. **运行时健壮性**（S1/S2/S4）——异步生命周期与内存边界，崩溃路径明确；
3. **UI 层工程质量**（M5–M9、M17、测试缺口）——性能与可维护性债务，随文章长度与功能迭代持续放大。

建议按上述 P0→P3 顺序推进；**P0 完成前不建议发布新版本**。
