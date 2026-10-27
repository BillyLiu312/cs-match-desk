# CS Match Desk

[![macOS](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5-orange?logo=swift)](https://www.swift.org/)
[![CI](https://github.com/BillyLiu312/cs-match-desk/actions/workflows/ci.yml/badge.svg)](https://github.com/BillyLiu312/cs-match-desk/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/Code%20License-MIT-green.svg)](LICENSE)

一个原生 macOS 菜单栏应用，用简洁的桌面面板查看 Counter-Strike 2 比赛、直播比分和近期赛果。

> Native macOS menu bar app for Counter-Strike 2 schedules, live scores, and recent results. The interface is currently localized in Simplified Chinese.

## 功能

- 从 [HLTV Matches](https://www.hltv.org/matches) 已渲染的页面读取比赛信息
- 查看昨天、今天和明天的赛程，每次打开默认回到今天
- 按赛事分组，并按开赛时间升序排列
- 展示队伍、队标、BO 赛制、当前地图回合比分和系列赛胜图进度
- 焦点列表识别 IEM、PGL、ESL、BLAST、EWC、CAC 和 Major 赛事
- 当天没有重要赛事时，焦点列表自动回退到普通赛程
- 展示重要赛事的已结束比赛、最终比分和 HLTV 详情链接
- 焦点与全部列表互斥，避免同一比赛重复出现
- 为黑色队标提供深色模式反色资源
- 每 5 分钟自动刷新，支持手动刷新与本地缓存
- 点击比赛卡片可在默认浏览器打开对应 HLTV 页面

## 系统要求

- macOS 13 Ventura 或更高版本
- Apple Silicon 或 Intel Mac（源码可按当前架构构建）
- Xcode Command Line Tools；建议使用完整 Xcode
- 可正常访问 `hltv.org` 的网络环境

应用本身不要求 VPN。如果当前网络无法在 Safari 中访问 HLTV，应用也需要使用系统代理或 VPN。

## 快速开始

```bash
git clone https://github.com/BillyLiu312/cs-match-desk.git
cd cs-match-desk
./scripts/run.sh
```

菜单栏出现 CS Logo 后，点击即可打开面板。

## 构建应用

```bash
./scripts/build-app.sh
open "build/CS Match Desk.app"
```

生成产物位于 `build/CS Match Desk.app`。本地构建使用 ad-hoc 签名，不包含 Apple Developer ID 公证。若长期使用，可以将应用拖入 `/Applications`，并在“系统设置 -> 通用 -> 登录项”中添加开机启动。

## 测试

```bash
./scripts/test.sh
```

测试脚本会编译核心比赛模型并检查日期过滤、重要赛事识别、排序、标签去重、BO 胜图展示及战队简称。

## 工作原理

HLTV 没有为本项目提供公开、稳定的官方比赛 API，并会对普通 HTTP 抓取返回 Cloudflare 验证。应用因此使用 macOS WebKit 在本机正常加载网页，再读取页面中已经渲染的比赛卡片：

```text
HLTV 页面 -> 隐藏 WKWebView -> DOM 提取 -> Match 模型 -> 本地缓存 -> SwiftUI 菜单栏面板
```

- 应用不会尝试绕过验证码或其他访问控制。
- 抓取失败时继续展示最近一次成功缓存。
- 页面结构发生变化后，`HLTVScraper.swift` 中的选择器可能需要更新。
- 为控制请求频率，默认刷新间隔为 5 分钟。

## 项目结构

```text
Sources/CSMatchBar/
  CSMatchBarApp.swift    菜单栏应用入口
  DashboardView.swift   比赛面板与卡片界面
  HLTVScraper.swift     WebKit 页面加载与 DOM 提取
  Match.swift           比赛模型和筛选规则
  MatchesStore.swift    刷新、缓存和视图状态
  TeamLogoCache.swift   队标资源与深色模式切换
Resources/              应用图标、菜单栏图标和队标资源
Tests/                  零依赖核心逻辑检查
scripts/                运行、测试、打包和资源生成脚本
```

## 隐私

- 不需要账户，不收集用户身份信息。
- 不包含遥测、分析 SDK 或广告 SDK。
- 比赛缓存和队标缓存仅保存在本机。
- 点击比赛时会使用系统默认浏览器打开 HLTV。

## 已知限制

- HLTV 的 Cloudflare 安全验证可能导致临时刷新失败。
- HLTV DOM 或赛事页面结构变化可能导致字段缺失。
- 昨日赛果依赖最近的成功同步与缓存。
- 预装队标来自构建时的 VRS 常见队伍快照，阵容和排名会随时间变化。
- 当前应用界面仅提供简体中文。

## 贡献

欢迎提交 Issue 和 Pull Request。开始前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)。安全问题请按照 [SECURITY.md](SECURITY.md) 私下报告。

## 免责声明

本项目是非官方社区项目，与 HLTV、Valve、Counter-Strike、赛事主办方或任何战队均无隶属、授权或背书关系。赛事数据可能延迟或不完整，不应将本应用作为投注或其他高风险决策的唯一信息来源。

## 许可证与资源

源代码使用 [MIT License](LICENSE)。HLTV 队标、赛事与战队商标，以及用户提供的图片不包含在 MIT 授权范围内；它们仍归各自权利人所有。详情见 [NOTICE.md](NOTICE.md)。
