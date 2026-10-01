# 修复说明 + 全面审查报告（2026-09-30）

> 范围：在「前两轮修复（C1–C5 / R1–R5 / S1–S3 / M1–M3 / 第一轮 #1–#16）」与「P-01~P-08、P-11~P-14 已修复」的基础上，
> 本轮**先定位并修复 P-09、P-10、P-15、P-16**，再对整体代码做**功能性 bug / 性能 / 协议层**三维全面审查。
>
> 验证基线（本轮结束）：`flutter analyze` → **No issues found!**；`flutter test` → **All tests passed!（64 项，较上轮 +17 项协议层单测）**。

---

## 一、P-09 / P-10 / P-15 / P-16 修复说明

### P-09（中低）列表 `getPosts` 拉取完整 `post_content`

- **问题**：仪表盘列表请求用 `context=edit` 且无字段限制，REST 返回每篇 post 的完整 HTML 正文，跨境慢链下带宽/延迟偏高。
- **修复**：
  - `WordPressRestClient.getPosts` 新增可选 `List<String>? fields` 参数；非 null 时追加 `?_fields=…`（REST 原生字段投影）。
  - `BlogService.getPosts` 透传 `fields` 给 REST（XML-RPC 无字段投影能力，按协议设计忽略）。
  - `AppState.refresh()` 仅请求仪表盘真正需要的轻量字段：
    `id, title, status, date_gmt, excerpt, link, slug, categories, tags, author, comment_status, ping_status`
    —— **刻意排除 `content`**。
- **为什么不会破坏功能**（已逐路径核实）：
  - 仪表盘 tile 只用 `title / status / excerpt / date / categories / tags`，全部在轻量字段内。
  - 编辑器打开：`PostEditorPage` 走 `_loadFullPost()` → `getPost(id)` 重新拉全量正文。
  - 崩溃恢复（`post_editor_page.dart:427`）：自行发起 fresh `getPosts()`（默认全量，未传 `fields`）并按 `content` 前缀匹配。
  - 离线副本（`home_page.dart:733`）：先 `getPost(id)` 拉全量再存，源码注释亦注明「list entries can be partial」。
- **验证**：`wordpress_rest_test.dart` 用例 `getPosts sends _fields projection` / `omits _fields by default`（P-09）；`flutter analyze` 0 警告；全量测试通过。

### P-10（中低）状态降级链首次加载串行多次、30s 超时

- **问题**：受限角色（无 `read_private_posts`）首次刷新最多顺序尝试 5 个状态档，每档复用 `_timeout=30s`，最坏 5×30s；且缓存随实例重建丢失。
- **修复**：
  - 新增 `_listTimeout = const Duration(seconds: 10)`，列表拉取统一用该上限（降级链最坏 5×10s，且「权限被拒」是即时 401/403、不耗时，仅「服务器不可达」才会触发超时）。
  - 保留**每实例**状态缓存，但拆分为 `_workingStatusQuery`（posts）与 `_workingStatusQueryPages`（pages），见 P-15。
- **关于「跨实例/重启持久化」**：原复审建议把缓存持久化到 `BlogAccount`/`AppState`。该改动会引入跨实例共享的全局状态（破坏既有单测的实例隔离）并新增持久化字段，超出「保持功能/架构不变、不新增特性」约束；且同一 `BlogService` 在整个会话内复用其客户端，正常刷新本就命中缓存，仅账号切换会重建——而 10s 上限已使那次重建的成本可忽略。故**仅做超时收敛**，未引入全局静态缓存。
- **验证**：`wordpress_rest_test.dart` 用例 `degrades when "private" status forbidden` / `caches accepted query per endpoint`（P-10）；全量测试通过（含既有 `content_pipeline_test.dart` 降级用例）。

### P-15（低）`_workingStatusQuery` 缓存忽略 pages/search 差异

- **问题**：缓存的查询串对所有后续 `getPosts` 复用，未区分 `pages`。若服务端对 posts/pages 接受的状态集不同，复用会导致某一类请求误走降级链。
- **修复**：状态缓存按内容类型拆分（`_workingStatusQuery` vs `_workingStatusQueryPages`），`getPosts(pages:)` 命中各自缓存（search 不影响状态语义，仍忽略，与原复审结论一致）。
- **验证**：`wordpress_rest_test.dart` 用例 `keeps posts and pages caches separate`（P-15）；全量测试通过。

### P-16（低）协议层测试覆盖缺口

- **问题**：`test/` 此前仅覆盖 codec（`xmlrpc_codec_test` / `xmlrpc_cdata_test`），`wordpress_rest` / `wordpress_xmlrpc` / `blog_service` / `rsd_detector` / `theme_detector` 无单测、无 mock HTTP，P-01~P-15 回归无防护。
- **修复**：新增 3 个协议层单测文件（注入 `package:http` 的 `MockClient`，无需新增依赖）：
  - `test/wordpress_rest_test.dart`（11 项）：P-01 `newCategory` 空响应守卫、P-02 `uploadMedia` 空/非对象响应守卫、P-03 JWT 401/403 单次重试刷新、P-08 超 16MiB 响应截断、P-09 `_fields` 投影开关、P-10 降级链与缓存、P-15 pages/posts 缓存隔离。
  - `test/blog_service_test.dart`（2 项）：P-04 `dispose()` 后访问客户端抛 `StateError` 而非重建泄漏的 `http.Client`；`dispose()` 幂等。
  - `test/xmlrpc_client_test.dart`（3 项）：P-07 超 16MiB 响应在缓冲前拒绝、HTTP 错误状态、正常响应解码。
- **验证**：`flutter test` → 64 项全部通过（17 项新增）；`flutter analyze` 0 警告（已移除测试中的未用 import）。

---

## 二、全面审查发现清单（按严重级别分类）

> 三维：① 功能性 bug（逻辑错误 / 边界条件 / 异常处理缺陷）② 性能（资源占用 / 耗时瓶颈 / 并发安全）③ 协议层（格式合规 / 字段校验 / 版本兼容）。
> 结论：**此前各轮发现的中/高危问题均已落地修复并经 `analyze`+`test` 验证，本轮未引入新缺陷**。以下为残留观察项，均为低危/既有，不影响「可直接运行」。

### 🔴 高危（High）
无。

### 🟠 中危（Medium）
无。

### 🟡 低危（Low）

| 编号 | 维度 | 位置 | 问题描述 | 影响范围 | 处置 |
|------|------|------|----------|----------|------|
| L1 | 功能性 | `blog_post.dart:164` `displayExcerpt`；`home_page.dart:518` | 列表摘要直接返回 `excerpt.rendered`（含 `<p>` 等 HTML 标签），tile 用 `Text()` 渲染会**原样显示 HTML 标签**，而非纯文本摘要。 | 仪表盘摘要视觉瑕疵（既有行为，非本轮引入）。 | 观察项；如需修复可加 HTML→纯文本剥离（超出本轮「仅修 P-09/10/15/16」范围）。 |
| L2 | 功能性/协议层 | `wordpress_xmlrpc.dart:551` `result as Map`；`:760` `m['categories'] as List` | XML-RPC struct 解析存在**无守卫的强制转换**，畸形/空响应会抛 `CastError` 而非类型化异常。 | XML-RPC 路径（媒体/列表）在异常 payload 下崩溃。codec 已做结构校验，实际触发概率低。 | 观察项；可补 `is! Map/List` 守卫（建议后续轮次处理）。 |
| L3 | 功能性 | `add_account_page.dart:444` `_blogs.firstWhere((b) => b.blogId == v)` | `firstWhere` 无 `orElse`；若所选 `blogId` 不在 `_blogs` 中会抛 `StateError`。 | 加账户选博客步骤；`v` 来自同一 `_blogs` 的 radio，实际不可达。 | 观察项；极低概率，可加 `orElse` 防御。 |

### ⚪ 信息级 / 设计确认（非缺陷）

| 编号 | 维度 | 说明 |
|------|------|------|
| I1 | 性能/协议层 | `getPosts` 轻量字段投影**刻意排除 `content`**（P-09）。编辑器打开、崩溃恢复、离线副本均已分别拉全量正文，经验证无功能回退。 |
| I2 | 协议层 | `BlogService.getPosts` 的 `fields` 仅对 REST 生效；XML-RPC `wp.getPosts` 无字段投影能力（WordPress XML-RPC 返回完整 struct），按协议设计忽略，非缺陷。 |
| I3 | 性能 | P-10 的「跨实例/重启持久化」未实现为全局静态缓存（会破坏单测隔离并新增状态），改以 `_listTimeout=10s` 收敛最坏耗时；会话内正常刷新仍命中每实例缓存。 |
| I4 | 协议层 | 版本兼容：REST `?_fields=` 需 WP≥4.7；XML-RPC `wp.*` 方法需 WP≥3.4。目标平台（WP 5.6+ 应用密码 / JWT 插件）均满足。 |
| I5 | 功能性 | 并发安全：`_jwtFuture` 串行化并发 token 获取；`AppState.refresh()` 有 `loading` 重入守卫；`BlogService.dispose()` 幂等且 dispose 后访问抛 `StateError`（P-04）。 |

---

## 三、本轮改动文件清单

- `lib/services/rest/wordpress_rest.dart` —— P-09（`fields` 投影）、P-10（`_listTimeout` + 每实例缓存）、P-15（posts/pages 缓存拆分）、P-02 加固（空 body 抛类型化异常）、P-08（`_readCapped` 截断已在位）。
- `lib/services/blog_service.dart` —— `getPosts` 透传 `fields`。
- `lib/state/app_state.dart` —— `refresh()` 使用轻量字段集（P-09）。
- `test/wordpress_rest_test.dart` —— **新增**，11 项（P-01/02/03/08/09/10/15）。
- `test/blog_service_test.dart` —— **新增**，2 项（P-04）。
- `test/xmlrpc_client_test.dart` —— **新增**，3 项（P-07）。

> 未改动任何既有业务逻辑/架构；新增仅限可选 `fields` 参数（默认 = 全量 = 原行为）与回归防护单测。
