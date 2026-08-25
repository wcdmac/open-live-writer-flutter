# Starmaster Writer

Starmaster Writer 是一个跨平台 WordPress 博客写作客户端（Flutter 实现），支持 Windows、Linux、macOS、iOS 和 Android。

基于 Open Live Writer（MIT License, .NET Foundation）的产品理念与协议行为，使用 Dart/Flutter 完全重写。

## 功能

- **双模式编辑器**：可视化（所见即所得）块编辑器 + HTML 源代码模式，实时预览
  - 可视化模式支持：段落、标题（H1–H6）、图片（设备上传到媒体库/URL）、表格（行列增删、表头）、视频（YouTube/MP4/iframe 嵌入）
  - WordPress 块注释（Gutenberg 标记）在往返编辑中完整保留
  - 未识别的 HTML 进入"源码块"，永不丢失
- **WordPress 双协议**：XML-RPC（WordPress / MetaWeblog / MovableType / Blogger）与 REST API v2（应用程序密码 / JWT）
- **站点自动检测**：RSD 探测、主题样式检测（预览跟随博客主题配色）
- **完整文章管理**：草稿/发布/排期/私有、分类、标签、摘要、slug、评论开关
- **CI/CD**：GitHub Actions 五平台自动构建与 Release 发布

## 致谢

本项目的架构设计与 WordPress 交互协议参考自 [Open Live Writer](https://github.com/OpenLiveWriter/OpenLiveWriter)（MIT License, Copyright .NET Foundation）。

## 构建

```bash
flutter pub get
flutter run          # 或 flutter build <platform> --release
flutter test         # 运行测试
```
