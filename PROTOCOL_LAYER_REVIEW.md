# 协议层代码复审报告（第三轮）

> 范围：`lib/services/rest/wordpress_rest.dart`、`lib/services/xmlrpc/*`（client / wordpress / codec）、
> `lib/services/blog_service.dart`（门面）、`lib/services/rsd_detector.dart`、`lib/services/theme_detector.dart`、
> `lib/views/add_account_page.dart`（加账户协议流程）。
> 目标：在前两轮修复的基础上，**再次审查**，排查当前代码中仍存在的 bug 与性能瓶颈，
> 给出严重程度、影响范围与「修复 / 优化建议方向」（本轮只做审查，不改代码）。

## 一、结论速览

第一轮、第二轮发现的缺陷（C1–C5、R1–R5、S1–S3、M1–M3，以及第一轮 #1–#16）**均已落地且 `flutter analyze` 0 错误、`flutter test` 47/47 通过**。
但本次复审在「当前代码」上仍发现 **15 个具体问题（P-01 ~ P-16）**，其中：

- **中（Medium）5 个**：P-01 `newCategory` 缺响应守卫、P-02 `uploadMedia` 缺响应守卫、P-03 JWT 过期无重试刷新、P-04 `BlogService.dispose()` 后 getter 泄露 http.Client、P-07 XML-RPC 体积上限在缓冲后才校验（S3 修复不完整）。
- **中低 3 个**：P-08 REST 无响应体积上限、P-09 列表拉取完整正文、P-10 状态降级链首次加载串行多次请求。
- **低（Low）7 个**：P-05 标签串行创建 + 空响应静默丢、P-06 RSD 整段吞错、P-11 主题 CSS 反复全量正则、P-12 RSD 探测串行、P-13 XML-RPC 显式状态不降级、P-14 日期解析协议不一致、P-15 缓存忽略 pages/search、**P-16 协议层测试覆盖缺口**。

> 说明：P-07 / P-03 / P-16 是对「已修复项」的**深化**——S3 只防了解码未防缓冲、JWT 401 未自动重试、协议层几乎无测试。其余均为前两轮未覆盖的新问题。

---

## 二、问题清单（按严重程度）

| 编号 | 位置 | 问题 | 严重程度 | 影响范围 |
|------|------|------|----------|----------|
| P-01 | `wordpress_rest.dart:529` | `newCategory` 未对 `data` 做 `is! Map` 守卫 | 中 | 「新建分类」遇异常响应崩溃 |
| P-02 | `wordpress_rest.dart:606` | `uploadMedia` 对 `jsonDecode(...) as Map` 未守卫 | 中 | 媒体上传空响应崩溃 |
| P-03 | `wordpress_rest.dart:133-209` | JWT 401/403 后仅清 token，不重试当前请求 | 中 | JWT 账号 token 过期后持续 401 至重启 |
| P-04 | `blog_service.dart:22-37,163` | `dispose()` 后 `rest`/`xmlrpc` getter 重建孤儿 http.Client | 中 | 账号切换/移除后连接池泄漏，长期 socket 耗尽 |
| P-07 | `xmlrpc_client.dart:58-72` | `_maxResponseBytes` 在 `fromStream` 完整缓冲后才校验（S3 不完整） | 中 | 恶意/故障服务器以超大响应打爆内存（DoS） |
| P-08 | `wordpress_rest.dart:191-213,597` | REST 路径无响应体积上限（与 XML-RPC 不对称） | 中低 | REST 同样存在内存耗尽风险 |
| P-09 | `wordpress_rest.dart:235-258` | 列表 `getPosts` 用 `context=edit` 拉取完整 `post_content` | 中低 | 仪表盘刷新带宽/延迟偏高 |
| P-10 | `wordpress_rest.dart:283-318` | 状态降级链首次最多 5 次串行请求，每次 30s 超时 | 中低 | 受限角色首次刷新慢；缓存随实例重建丢失 |
| P-05 | `wordpress_rest.dart:476-488` | 标签串行创建；空响应 `created['id']` 被 catch 静默丢弃 | 低 | 多新标签保存慢、部分标签静默丢失 |
| P-06 | `rsd_detector.dart:218` | RSD 解析整段 `catch(_) => null` 吞错（R2 只修了 theme） | 低 | 检测异常被掩盖，可能误判为 WP |
| P-11 | `theme_detector.dart:112-171` | `_themeFromCss` 对整段 CSS 反复正则扫描 | 低 | 每次刷新重复扫描大 CSS，CPU 浪费 |
| P-12 | `rsd_detector.dart:56-88` | REST 与 XML-RPC 探测串行执行 | 低 | 加账户检测阶段多一次串行往返 |
| P-13 | `wordpress_xmlrpc.dart:134-136` | 显式 status 失败不降级（与 REST R4 不对称） | 低 | 同角色切协议时筛选行为不一致 |
| P-14 | `wordpress_xmlrpc.dart:715-719` | XML-RPC 日期未归一化 UTC（与 REST 不一致） | 低 | 跨时区站点时间可能偏差 |
| P-15 | `wordpress_rest.dart:283-293` | `_workingStatusQuery` 缓存忽略 pages/search 差异 | 低 | 极低风险，记录以备 |
| P-16 | `test/` | 协议层（除 codec 外）无单测、无 mock HTTP | 低 | 全部 P-01~P-15 回归无防护 |

---

## 三、逐项说明与修复 / 优化建议

### P-01（中）`newCategory` 缺少响应类型守卫
- **现状**：`final data = await _request('POST', '/wp/v2/categories', body: {...});` 后直接 `data['id']` / `data['name']` / `data['slug']`。
  同一文件里 `newPost` / `editPost` / `getPost` 都做了 `if (data is! Map) throw WordPressRestException(...)`，唯独 `newCategory` 与 `uploadMedia` 漏了。
- **触发**：服务端对创建分类返回空 body（`_request` 返回 `null`）或非对象（返回 `[]`）时，`null['id']` / `List['id']` 抛 `NoSuchMethodError` / `CastError`，而非类型化异常。
- **影响**：新建分类功能在异常响应下崩溃，而非给出「创建失败」提示。
- **建议**：在读取字段前加 `if (data is! Map) throw WordPressRestException(500, 'invalid_category', 'Bad category payload for "$name"');`，与 `newPost` 对齐。

### P-02（中）`uploadMedia` 对响应 `as Map` 未守卫
- **现状**：`final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map;`（line 606）。状态 `>= 400` 已先抛出，但 **200 + 空 body** 时 `jsonDecode` 返回 `null`，`null as Map` 抛 `CastError`。
- **影响**：媒体上传成功但服务器返回空响应时会崩溃。
- **建议**：`final data = jsonDecode(...); if (data is! Map) throw WordPressRestException(response.statusCode, 'media_upload_failed', 'Empty media response');`

### P-03（中）JWT 过期 / 401 后无自动重试刷新
- **现状**：`_request` 在 `statusCode == 401 && authMethod == jwt` 时 `_jwtToken = null`（line 207-209）。但**当前这次失败请求直接抛出**，下次调用才会重新 `_fetchJwtToken()`。且若服务器对过期 token 返回 **403**，`_jwtToken` 根本不被清。
- **影响**：JWT 账号 token 过期（通常数小时~数天）后，所有请求持续 401/403 失败，用户必须重启应用才能恢复。这是「会真实发生、且体验很糟」的缺陷。
- **建议方向**：
  1. 把 token 失效判断从「仅 401」扩展到「401 或 403（jwt 场景）」。
  2. 在 `_request` 内对 JWT 401/403 做**单次重试**：`catch` 到后清 token → 重新 `_headers()` → 再发一次，避免把过期错误直接抛给上层。
  3. 也可抽成一次性 token-refresh 守卫（用 `_jwtFuture` 串行化），与现有并发去重机制一致。

### P-04（中）`BlogService.dispose()` 后 getter 重建孤儿 http.Client（连接泄漏）
- **现状**：`rest` / `xmlrpc` 是惰性 `??=` getter；`dispose()` 同时把 `_rest = null` / `_xmlrpc = null`。任何在 `dispose()` **之后**对 getter 的访问都会**新建一个 `WordPressRestClient`（带全新 `http.Client`）**，而新客户端不被任何字段引用、永不会被再次 `dispose()`。
- **触发**：账号切换 / 移除后，若有在途或滞后的 `async` 回调（如 `getPosts` / `editPost` 的 `Future`、或 `PopScope` 取消前的保存）仍持有该 `BlogService` 并调用方法。
- **影响**：每次泄漏一个连接池，长期累积可能耗尽 socket（尤其在频繁切换账号的移动端）。
- **建议方向**：引入 `_disposed` 标志；getter 在已 dispose 后抛 `StateError('BlogService 已释放，不可再用')`，由调用方保证不再使用——而不是静默重建。或更稳妥：客户端在构造时一次性持有、永不重建。

### P-07（中）XML-RPC 体积上限在「完整缓冲后」才校验（S3 修复不完整）
- **现状**：`xmlrpc_client.dart` 先 `response = await http.Response.fromStream(streamed)`（line 58，把**整个响应体读进内存**），再 `if (response.bodyBytes.length > _maxResponseBytes) throw`（line 66）。
  也就是说，上限只防住了「解码超大 body」，但**没防住「缓冲超大 body」**——一个返回 2GB 的服务器会先把 2GB 全部读进内存，上限检查才触发。
- **澄清**：`package:xml` 是非校验解析器，默认**不解析外部 DTD / 外部实体**，所以真正的 XXE（外部实体读取）在解析器层已被缓解；`billion-laughs` 内部实体展开在该库下也不会自动展开。因此 S3 的真实价值在于「**防止超大响应打爆内存**」，而当前的校验位置使这一价值落空。
- **影响**：恶意或故障服务器可用超大响应耗尽内存（DoS），尤其在低端设备。
- **建议方向**：手动读取流并累加字节计数，一旦超过上限**立即 `throw`**（`stream.takeWhile` / 自己 `await for`），在完整缓冲前中止。REST 路径同样应复用该 helper（见 P-08）。

### P-08（中低）REST 路径无响应体积上限（与 XML-RPC 不对称）
- **现状**：`_request` 用 `jsonDecode(utf8.decode(response.bodyBytes))`（line 213）、`uploadMedia` 同理（line 606），均无大小上限。
- **影响**：同 P-07，但作用在 REST。特别 `discoverRestRoot` 的 `/wp-json/` 探针、`uploadMedia` 的响应可能很大。
- **建议方向**：抽一个共享的「带字节上限的响应读取」helper，XML-RPC 与 REST 都用它，统一防护。

### P-09（中低）列表 `getPosts` 拉取完整 `post_content`
- **现状**：列表查询用 `context: 'edit'` 且未限制字段，REST 会返回每篇 post 的**完整 HTML 正文**；仪表盘 30 条即传输数 MB 列表根本用不到的内容。
- **影响**：仪表盘首次加载 / 刷新在跨境慢链下带宽与延迟明显偏高。
- **建议方向**：列表请求加 `_fields[]=id,title,status,date_gmt,excerpt,link`（REST 原生支持 `?_fields=`）。XML-RPC 核心 `wp.getPosts` 无字段限制能力，该路径可接受全量（或仅 metaWeblog 列表本就如此）。

### P-10（中低）状态降级链首次加载串行多次、30s 超时
- **现状**：`getPosts` 首次（无 `_workingStatusQuery` 缓存）最多顺序尝试 5 个状态档（line 294-316），每档复用 `_timeout = 30s`。受限角色 + 慢服务器最坏 5×30s 才结束。缓存仅在同实例内有效，服务一重建就丢失。
- **影响**：受限角色（Author/Contributor）首次刷新明显慢；`BlogService` 频繁重建时每次都重走降级链。
- **建议方向**：
  1. 降级探测用更短的单次超时（如 8–10s），整体最坏时长可控。
  2. 把「服务器接受的状态查询」持久化到 `BlogAccount` / `AppState` 级别，跨实例与重启复用。
  3. 可选：对最可能出现的 2 档（全状态档、`publish,draft,future,pending,trash` 无 private 档）并行探测，先赢为准。

### P-05（低）标签串行创建 + 空响应静默丢弃
- **现状**：`_resolveTagIds` 在 `for` 循环里对每个未知名称 `await _request('POST','/wp/v2/tags', ...)`（line 476）——**串行 N 次往返**；且 `created['id']` 在 `created == null`（空响应）时抛 `NoSuchMethodError`，被外层 `try/catch(_)` 吞掉，该标签被静默跳过。
- **影响**：带多个新建标签保存慢；个别标签可能无提示地丢失。
- **建议方向**：`if (created is! Map) continue;`（显式跳过而非靠异常）；用 `Future.wait(...)` 并行创建彼此独立的标签。

### P-06（低）RSD 解析整段吞错（R2 只修了 theme_detector）
- **现状**：`rsd_detector.dart:218` `catch (_) { return null; }` 把解析/网络错误完全隐藏，而 `theme_detector` 已在 R2 改为 `debugPrint`。
- **影响**：RSD 解析中途异常 → 返回 null → `detect()` 回退到「假设 WordPress(xmlrpc.php)」，可能误判非 WP 站点。
- **建议方向**：`catch (e) { if (kDebugMode) debugPrint('RsdDetector: parse failed: $e'); return null; }`。

### P-11（低）主题 CSS 反复全量正则扫描
- **现状**：`_themeFromCss` 中每个 `decl()` 都对**整段 CSS** 跑 `RegExp(...).firstMatch(css)`，约 10 次/次探测；`detect()` 在每次 `detectTheme()`（即每次刷新）都会重新拉 CSS 并重扫。
- **影响**：频繁刷新时重复扫描大 CSS（典型 50KB+），纯 CPU 浪费。
- **建议方向**：① 单次遍历抽取所需声明，预编译正则；② 按 `homepageUrl` 缓存 `BlogTheme`（主题极少变），刷新直接复用。

### P-12（低）RSD 检测 REST 与 XML-RPC 串行
- **现状**：`detect()` 先 `discoverRestRoot`（REST），再 `_detectFromHomepage`（XML-RPC），二者无依赖。
- **影响**：加账户检测阶段多一次串行往返延迟。
- **建议方向**：`await Future.wait([discoverRestRoot(...), _detectFromHomepage(...)])`，注意二者共享同一 `_http` 客户端（已正确传入 `client:` 避免重复关闭）。

### P-13（低）XML-RPC 显式 status 失败不降级
- **现状**：`wordpress_xmlrpc.getPosts` 对 `status != null` 直接 `return await wpGetPosts(status.wpValue)` 并 rethrow；而 REST 的 `getPosts` 已对显式 status 做降级链（R4）。
- **影响**：同一受限角色下，切到 XML-RPC 协议时「按状态筛选」直接报错，行为不一致。
- **建议方向**：把 XML-RPC 显式 status 尝试也包进与 REST 相同的降级回退。

### P-14（低）XML-RPC 日期未归一化 UTC（与 REST 不一致）
- **现状**：REST `parseDate` 正确处理 `date_gmt` + 时区后缀；XML-RPC `_postFromWpStruct.parseDate` 直接信任 `DateTime` 原始值或 `DateTime.tryParse(raw)`，未做 UTC/本地归一。XML-RPC 返回的日期常为服务器本地时间。
- **影响**：跨时区站点在 XML-RPC 协议下，创建/发布时间可能显示偏差。
- **建议方向**：在 `_postFromWpStruct` 内对 XML-RPC 日期做与 REST 一致的 UTC 归一（按 `wp.post_date_gmt` 优先，缺失时按 `post_date` + 站点时区规则处理）。

### P-15（低）`_workingStatusQuery` 缓存忽略 pages/search
- **现状**：缓存的查询串对所有后续 `getPosts` 复用，未区分 `pages`/`search`。`status == null` 仪表盘场景无碍，记录以备。
- **影响**：极低；若未来按页/搜索分别请求，状态查询不会自适应。
- **建议方向**：缓存 key 含 `pages` 维度（search 不影响 status 语义，可忽略）。

### P-16（低）协议层测试覆盖缺口
- **现状**：`test/` 下仅 `xmlrpc_codec_test.dart`、`xmlrpc_cdata_test.dart` 覆盖协议层；`wordpress_rest.dart` / `wordpress_xmlrpc.dart` / `blog_service.dart` / `rsd_detector.dart` / `theme_detector.dart` **无单测、无 mock HTTP**。
- **影响**：P-01~P-15 中绝大多数（空响应、401、trash-on-create、状态降级、dispose 后泄漏）本可用 mock client 在单测中捕获，目前回归无防护。
- **建议方向**：用 `package:mockito` 或 `http_test_client` 注入假 `http.Client`，对 REST + XML-RPC + `BlogService` 做：空 body、非对象 body、401/403、trash 降级、状态降级链、dispose 后调用。把这作为「修复 P-01~P-15 的护栏」一并补上。

---

## 四、优先级与落地建议

1. **先修正确性 / 资源类（中）**：P-01、P-02（简单守卫，几分钟）、P-04（dispose 后防泄漏，重要）、P-03（JWT 重试，体验关键）、P-07+P-08（统一流式体积上限，安全）。
2. **再修性能（中低）**：P-09（`_fields` 限制）、P-10（降级链超时 + 持久化缓存）。
3. **低优清理**：P-05、P-06、P-11、P-12、P-13、P-14、P-15。
4. **配套护栏**：P-16 单测，与上述修复同步补齐，避免再次回归。

> 本轮仅完成「复审 + 建议」。如需我按上述优先级**直接落地修复**（保持现有功能与逻辑不变、并补 P-16 单测），告诉我即可。
