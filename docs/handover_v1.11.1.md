# open_live_writer 交接文档（v1.11.1 发版后）

> 编写人：泓儿 ｜ 编写时间：2026-10-06 ｜ 仓库 HEAD：`8ac460e`（`main`，工作树干净）
> 版本：`v1.11.1`（pubspec `1.11.1+32`）｜ 分支策略：单 `main` 分支 + `tmp/**` 临时分支
> 说明：本文档中「主人」= 本项目产品负责人 / 需求方；「接手同事 / 后续维护者」= 本文档读者。

---

## 0. 一句话现状

v1.11.0 之后的全部审查缺陷（N1–N8 + 遗留、F1–F6、G1、H1）已修复，并随 **v1.11.1** 正式发版闭环。
**关键环境约束**：本地 Flutter 工具链被 SenseShield 驱动阻断，无法本地 `analyze/test/build`，开发与验证**完全依赖 GitHub Actions CI（唯一真值）**。当前无硬阻塞，仅有主动 deferred 项与一项测试覆盖缺口。

---

## 1. 当前任务清单及状态

| 轮次 | 范围 | 状态 | 落点 |
|------|------|------|------|
| v1.10 审查 | 16 项（P1×4） | ✅ 全部修复 | 历史 |
| v1.11 复审 | N1–N8 + 遗留项 | ✅ 全部修复或文档化 | `main` |
| 复审 #1 | F1–F6 + Wave C（记录项） | ✅ 全部修复（CI 全绿） | `c88864c` |
| 复审 #2 | G1（P3 小重构） | ✅ 修复（该修引入 H1） | `09aa3d7` |
| 复审 #3 | H1（P3 oversize 资源泄漏） | ✅ 修复（本次发版） | `c9d74b1` |
| 发版 | v1.11.1 | ✅ 已发（8 产物，CI 全绿） | tag `v1.11.1` |
| 主动 deferred | `_emit` 真机长文输入 profiling（Wave C 留项） | ⏸ 未做（非阻塞） | — |
| 测试缺口 | MediaCache oversize 确定性单测 | ⏸ 未做（无 DI，超出 H1 范围） | — |

**结论**：所有已知审查项已闭环；代码质量持续收敛。剩余两类未做项均为「主动 deferred / 覆盖增强」，不构成功能阻塞。

---

## 2. 本次发版已完成的具体内容与交付物

### 2.1 版本与流程
- `pubspec.yaml`：`1.11.0+31` → `1.11.1+32`（提交 `d031682`）。
- 打 annotated tag `v1.11.1`（消息含累计修复 F1–F6 / G1 / H1），push 触发全量 `Build & Release`。
- CI run `37258068514`：**7/7 全绿**（Analyze&Test + Build Linux/Android/macOS/iOS + Windows + Publish GitHub Release）。
- 发布页：https://github.com/wcdmac/open-live-writer-flutter/releases/tag/v1.11.1

### 2.2 累计修复清单（自 v1.11.0）
- **F1**（P2）：`media_cache` idle `onTimeout` 改 `s.addError(HttpException)`，同时补完 N3/N4（截断 tmp 不再被提升为缓存命中）。
- **F2**（P3）：下载加 5min 总超时（对称上传路径）。
- **F3/F4**（P3）：`app_state.refresh()` 代际守卫（错误赋值 + `notifyListeners` 前二次校验），防切账号串号。
- **F5**（P3）：`discoverRestRoot` `utf8.decode(bytes, allowMalformed: true)`，避免多字节截断抛 FormatException。
- **F6**（P3 记录）：`insert_bar` 上传「取消」仅放弃结果，补注释说明 orphan-file 局限。
- **G1**（P3）：`MediaCache.fetch` 流式下载改手动 `StreamSubscription` + idle/total 双 Timer，超时真正 `sub.cancel()` 止流（修复 F2 尾巴）。
- **H1**（P3）：oversize 哨兵分支补 `sink.close()` + `tmp.delete()`，修复 G1 引入的 `.tmp`/句柄泄漏。

### 2.3 交付物（GitHub Release，8 个产物）
`app-arm64-v8a-release.apk`、`app-armeabi-v7a-release.apk`、`app-x86_64-release.apk`、`app-release.aab`、
`open-live-writer-ios-unsigned.ipa`（未签名 + Verify IPA unsigned）、`open-live-writer-linux-x64.tar.gz`、
`open-live-writer-macos.zip`、`open-live-writer-windows-x64.zip`。

### 2.4 源码 / 测试改动文件（main vs v1.11.0）
**源码（10 个）**
- `lib/services/media_cache.dart`（N3/N4/F1/F2/G1/H1 核心）
- `lib/state/app_state.dart`（N1/F3/F4）
- `lib/services/rest/wordpress_rest.dart`（N5/F5/Wave C）
- `lib/editor/blocks/insert_bar.dart`（N7/N8/F6）
- `lib/editor/editor_controller.dart`（N2/Wave C）
- `lib/editor/block_document.dart`（N6）
- `lib/models/blog_post.dart`、`lib/services/xmlrpc/wordpress_xmlrpc.dart`、`lib/state/editor_state.dart`、`lib/views/post_editor_page.dart`（遗留项）

**测试（4 个）**
- `test/block_editor_n2_test.dart`（NEW，N2 防抖竞态丢字回归）
- `test/editor_controller_test.dart`（同步即时断言）
- `test/block_document_test.dart`（嵌套 div 分栏）
- `test/wordpress_rest_discovery_test.dart`（NEW，F5 截断多字节 + 正常 routes）

### 2.5 H1 具体改动（本次发版最直接的一处）
文件 `lib/services/media_cache.dart`，`fetch()` 的 oversize 哨兵分支：
- G1 重构删掉了原 oversize 路径内联的 `await sink.close(); await tmp.delete();`，仅留 `fail(哨兵) + return`；外层 `catch` 哨兵分支旧注释「temp already deleted above」已过时，直接 `return null` → 每次超限（>32MB）泄漏最大 32MB 的 `.tmp` + 未关句柄（Windows 锁文件）。
- 修复：哨兵分支补 `try { await sink.close(); } catch (_) {}` + `try { await tmp.delete(); } catch (_) {}` 再 `return null`；修正两处过时注释（原 L211、L233）；顺带把原 L172-229 不齐缩进按 Dart 规范重排（纯格式）。

---

## 3. 卡住的问题、阻塞原因及影响范围

| 问题 | 类型 | 阻塞原因 | 影响范围 |
|------|------|----------|----------|
| 本地 Flutter 工具链被 SenseShield 阻断 | 环境阻塞（硬） | 本机 `flutter`/`dart` 命令被驱动拦截，无法本地 analyze/test/build | 所有验证依赖 CI：tmp/** 分支 push 触发 Analyze&Test（~1–6min），tag 触发全量 Build&Release（~6min）。**若 CI 不可用则完全无法验证/发版** |
| MediaCache oversize 无确定性单测 | 测试覆盖缺口（软） | `MediaCache._client` 是私有 `final` 字段、不可注入；确定性 oversize 单测需真实本地服务器或 DI 重构，超出 H1「几行小改动」范围 | 回归风险低但非 0；当前以 Analyze&Test 全绿 + 代码审查保证 |
| `_emit` 每键全量 `serializeBlocks` 成本未做真机 profiling | 主动 deferred（非阻塞） | Wave C 留项，主人此前未要求执行 | 长文实时输入性能未知，属已知权衡，不影响发版 |
| P0–P3 功能项 | — | 已全部收口（见 implementation_status.md「Deferred」节实为已收口清单） | 无功能阻塞 |

**结论**：无硬功能阻塞；唯一硬约束是「本地工具链不可用、CI 为唯一真值」，接手同事必须接受「改一行也要走 CI 验证」的节奏。

---

## 4. 下一步计划与待办事项

1. **监控 v1.11.1 真机反馈**：重点验证 Windows 上 H1 修复后的句柄释放（超限下载后 `.tmp` 消失、无文件锁残留）。
2. **若继续功能开发**：先跑一轮真机长文输入 profiling，确认 `_emit` 每键全量 `serializeBlocks` 成本是否需优化（Wave C 留项）。
3. **测试增强（建议）**：给 `MediaCache` 注入可控 `http.Client`（DI 重构），并加单测断言「超限返回 null 且无 `.tmp` 残留」，把 oversize 行为锁死。
4. **常规改动流程（必须遵守）**：
   - 新建 `tmp/<topic>` 分支 → 提交 → push → 等 CI `Analyze & Test` 全绿；
   - `git checkout main && git merge --ff-only tmp/<topic> && git push`；
   - 删临时分支（本地 `git branch -d` + 远端 `git push origin --delete`）。
5. **发版流程**：升 `pubspec` 版本号（`versionName+buildNumber`，buildNumber 递增）→ 提交 `main` → 打 annotated `v*` tag → push tag 触发全量 Build&Release。
6. **CI 守卫须知**：`build.yml` 中 5 个构建 job 仅 `refs/heads/main` 或 `refs/tags/v*` 触发；`tmp/**` 分支只跑 `Analyze & Test`（Release job 仅 tag 触发）。

---

## 5. 踩过的坑、故障根因与规避经验

1. **本地工具链 SenseShield 阻断**
   - 根因：本机 `flutter`/`dart` 被安全驱动拦截。
   - 规避：一切以 CI 为唯一真值；本地只做编辑与代码审查，验证全走 `tmp/**` 分支 + `gh run watch`。

2. **N2 widget 测试首跑失败**
   - 现象：`enterText` 找不到 `TextField`。
   - 根因：编辑器块默认只读（`HtmlWidget`），需先 `tap` 进入编辑态才出现可编辑 `TextField`。
   - 规避：widget 测试先 `tap` 聚焦段落，再 `enterText`。

3. **第二轮 CI 三处编译失败**
   - `Future.timeout` 是实例方法非静态 → 包进 `Future.sync(() async { … })` 再 `.timeout`。
   - `MockClient` 仅返 `http.Response`（非流式）→ 改用 `http.BaseClient` 子类返回 `StreamedResponse`。
   - `onTimeout` 回调签名无参 / `TimeoutException` 非 const → 按真实签名与构造器修正。

4. **G1 实施时工具间歇性丢参数**
   - 现象：Edit/Read/Bash 报 `expected string, but received undefined`。
   - 规避：报错即重试，勿假设工具稳定；大改动前先 `git diff` 核对。

5. **GitHub API 429 限流**
   - 规避：等重置窗口后继续，勿高频轮询。

6. **G1 CI 失败 #1：括号失衡**
   - 根因：大块替换时删了内层 `try {` 却遗留对应 `} catch (e) {`，导致外层 `if` 不闭合。
   - 规避：大块替换后通读配对括号 / `dart analyze` 必过。

7. **G1 CI 失败 #2：`const TimeoutException`**
   - 根因：本 SDK（Flutter 3.47.6）中 `dart:io.TimeoutException` 构造器**非 const**；而 `dart:io.HttpException` **是 const**。混用导致编译失败。
   - 规避：写 `const` 异常前确认构造器是否 const；不确定就不加 `const`。

8. **commit message 反引号被 shell 替换吞掉**
   - 现象：含反引号的 message 被 bash 命令替换改写。
   - 规避：`git commit -m '单引号包 message'`（或文件传 `-F`）。

9. **H1（G1 引入的回归）**
   - 根因：G1 重构删除 oversize 路径的 `sink.close()+tmp.delete()` 时，未把清理职责转移到外层 `catch`，且旧注释「tmp 已删」掩盖了遗漏 → 泄漏 `.tmp`/句柄。
   - 经验：**重构删行时，必须核对所有控制流出口（成功 / 各异常哨兵）的清理职责是否完整转移**；过时注释是隐患温床，删代码同时删/改注释。

---

## 附录：关键事实速查

- **仓库**：`wcdmac/open-live-writer-flutter`，单 `main` 分支，发版靠 `v*` tag。
- **CI**：`.github/workflows/build.yml` — `on: push(main/tmp/**)` + `tags: ['v*']`。
- **发布页**：https://github.com/wcdmac/open-live-writer-flutter/releases/tag/v1.11.1
- **关键文件职责**：
  - `lib/services/media_cache.dart` — 图片磁盘缓存（下载/超时/超限/原子写盘），最易出资源泄漏，改动务必配对清理。
  - `lib/state/app_state.dart` — 刷新代际守卫（防切账号串号）。
  - `lib/services/rest/wordpress_rest.dart` — REST 客户端（字节上限 / utf8 / 路由发现）。
  - `lib/editor/editor_controller.dart` — 编辑内容同步（`_emit` 每键全量序列化，已知权衡）。
- **常用命令**：
  - 看 CI：`gh run watch <run_id>`；列运行：`gh run list --limit 8`。
  - 发版：`git tag -a vX.Y.Z -m "..." && git push origin vX.Y.Z`。
- **详细交付账**：见 `docs/implementation_status.md`（「已发布版本」表 + 各轮交付节）。
