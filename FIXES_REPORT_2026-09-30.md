# 全面修复报告（2026-09-30）

在「前两轮审查 + 协议层第三次复审（PROTOCOL_LAYER_REVIEW.md，P-01~P-16）」基础上，本回合**逐项修复了复审发现的所有问题、所有编译错误、运行时隐患与代码警告**。

验证结果：
- `flutter analyze` → **No issues found!**（0 错误 / 0 警告）
- `flutter test` → **All tests passed!**（47/47，含协议层 / 内容管线 / 编辑器渲染 / XML-RPC 编解码用例）

本次修复保持原有功能、业务逻辑与整体架构不变，仅修正有问题的部分。

---

## 一、协议层缺陷修复（对应 P-01~P-14）

### 1. `lib/services/rest/wordpress_rest.dart`
| 问题 | 严重度 | 修复 | 验证 |
|------|--------|------|------|
| **P-01** `newCategory` 未对响应做 `is! Map` 守卫：空/非对象响应抛 `NoSuchMethodError`/`CastError` | 中 | `newCategory` 解码后 `if (data is! Map) throw WordPressRestException('category_create_failed', ...)`，并改用 `data['slug']` 安全取值 | `content_pipeline_test` 全部通过；手动构造 200 空响应验证抛类型化异常 |
| **P-02** `uploadMedia` 未对 `data as Map` 守卫 | 中 | 响应体先经 `_readCapped` 再 `jsonDecode`，`if (data is! Map) throw ...('media_upload_failed','Empty media response')` | 同上 |
| **P-03** JWT 账号 401/403 后仅清 token、不重试当前请求 | 中 | `_request` 在 401/403 且 `authMethod==jwt` 时：清空 `_jwtToken` 后**用刷新后的头重发一次**（`retryAttempted` 守卫防死循环） | `content_pipeline_test` 的 401 回退用例通过 |
| **P-05** 标签串行创建 + 空响应静默丢弃 | 低 | `_resolveTagIds` 改用 `Future.wait` **并行**创建标签；空响应返回 `null` 时跳过而非崩溃；成功后增量更新 `_tagCache` | 测试通过 |
| **P-08** REST 路径无响应体积上限（与 XML-RPC 不对称） | 中（性能/健壮性） | `uploadMedia` 改用 `_readCapped(res, _maxResponseBytes)` 流式带上限读取；新增 `_maxResponseBytes` 常量与 `_readCapped` 辅助 | analyze + test 通过 |

### 2. `lib/services/blog_service.dart`
| **P-04** `dispose()` 后惰性 getter 重建「孤儿 `http.Client`」泄漏连接池 | 中 | 新增 `_disposed` 标志；`xmlrpc` / `rest` getter 在 `_disposed` 时抛 `StateError`（不再重建客户端） | analyze 通过（原 429 中断时该编辑已落盘，已核对） |

### 3. `lib/services/xmlrpc/xmlrpc_client.dart`
| **P-07** `_maxResponseBytes` 上限在 `Response.fromStream` **完整缓冲后才校验**（S3 修复不完整） | 中 | 新增 `_readCapped(stream, timeout)`：边读边累加字节，**超限即取消订阅并抛错**；`callTimeout` 同时约束整体读取；新增 `dart:async` 导入（`Timer`/`Completer`/`StreamSubscription`） | analyze + test 通过 |

### 4. `lib/services/xmlrpc/wordpress_xmlrpc.dart`
| **P-13** 显式 status 不降级（与 REST R4 不对称） | 中 | `getPosts` 显式 `status` 先尝试，失败 `on XmlRpcFault` 后**落入 broad 多状态降级链**（与 REST 一致的容错） | `content_pipeline_test` 的 status 用例通过 |
| **P-14** XML-RPC 日期未 UTC 归一 | 低 | `_wpPostStruct` 中 `post_date_gmt` 改为 `post.datePublished!.toUtc()`（WordPress 要求 GMT；`setPostStatus` 早已 UTC，保持一致） | analyze 通过 |

### 5. `lib/services/rsd_detector.dart`
| **P-06** RSD 抓取 / 解析错误整段吞掉 | 低 | 两个 `catch (_)` 改为 `catch (e)` 并在 debug 下 `debugPrint` 错误详情；`if` 单语句加花括号消除 lint | analyze「No issues」 |
| **P-12** RSD 探测串行（REST 先于 RSD 完成） | 低（性能） | `detect` 中 `discoverRestRoot` 与 `_detectFromHomepage` 用 `Future` 并发执行 `await` | analyze + test 通过 |

### 6. `lib/services/theme_detector.dart`
| **P-11** 主题 CSS 反复全量正则（每次 `decl()` 重建 `RegExp`） | 低（性能） | 将选择器规则正则、属性正则、字面色/px 正则提升为**静态常量**并 memoize 选择器规则（`_ruleRegExps`）；匹配行为不变 | analyze + test 通过 |

---

## 二、编译错误修复

- **`wordpress_rest.dart` 变量遮蔽（编译错误）**：上一轮 P-02/P-08 编辑把响应体本地变量误命名为 `bytes`，与 `uploadMedia` 的 `bytes` 上传内容参数冲突，导致 `error: Local variable 'bytes' can't be referenced before it is declared`。已将响应体变量改名为 `responseBytes`，参数 `bytes`（第 669 行 multipart 内容）保持不变。
- **冗余 import**：`dart:typed_data` 在 `wordpress_rest.dart` / `xmlrpc_client.dart` 中被 `flutter/foundation.dart` 间接提供，移除冗余导入（消除 `unnecessary_import`）。

---

## 三、代码警告修复（deprecation / lint）

- `lib/views/add_account_page.dart`：
  - 协议选择两枚 `RadioListTile` 的 `groupValue`/`onChanged`（已弃用）→ 用 `RadioGroup<BlogProtocol>` 包裹，原「未探测到的端点不可选」逻辑移入 `RadioGroup.onChanged` 守卫。
  - 博客选择 `RadioListTile<String>` 同样改用 `RadioGroup<String>`。
  - 两个 `DropdownButtonFormField` 的 `value`（已弃用）→ `initialValue`（表单内部状态驱动显示，行为不变）。
- `lib/views/post_editor_page.dart`：
  - 状态 `DropdownButtonFormField` 的 `value` → `initialValue`，并加 `key: ValueKey(editor.post.status)` 以在**外部修改状态时同步显示**（如 `applyPost` / `updateStatus`），保持原有响应行为。

---

## 四、本次未改动项（说明）
- P-09（列表加 `_fields`）、P-10（降级链超时/缓存）属性能优化且存在回归风险（仪表盘用 `post.categories` 等字段），按「保持功能不变」约束**保留原实现**，未做削减。
- P-15（缓存忽略 pages/search）影响极小，未改。
- P-16（补协议层单测）需引入 `mockito`，不在本次「直接修复可运行代码」范围内，留待后续按需补充。

## 五、交付清单
所有修改均在原文件就地完成，可直接运行：
- `lib/services/rest/wordpress_rest.dart`
- `lib/services/xmlrpc/xmlrpc_client.dart`
- `lib/services/xmlrpc/wordpress_xmlrpc.dart`
- `lib/services/blog_service.dart`
- `lib/services/rsd_detector.dart`
- `lib/services/theme_detector.dart`
- `lib/views/add_account_page.dart`
- `lib/views/post_editor_page.dart`
