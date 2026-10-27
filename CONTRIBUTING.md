# Contributing

感谢你考虑为 CS Match Desk 做贡献。

## 开始之前

1. 搜索现有 Issue，避免重复工作。
2. 对较大的功能或抓取策略变更，先创建 Issue 说明动机和方案。
3. 遵守 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)。
4. 不要提交凭据、Cookie、Cloudflare 验证数据或其他敏感信息。

## 本地开发

环境要求：macOS 13+，Xcode Command Line Tools 或完整 Xcode。

```bash
git clone https://github.com/BillyLiu312/cs-match-desk.git
cd cs-match-desk
./scripts/test.sh
./scripts/run.sh
```

打包应用：

```bash
./scripts/build-app.sh
```

## Pull Request 要求

- 保持修改范围清晰，避免无关格式化或重构。
- 用户可见行为变更需要同步更新 README。
- 核心筛选、排序或比分逻辑变更需要更新 `Tests/MatchChecks.swift`。
- HLTV DOM 选择器变更应说明使用的页面和验证日期。
- 新增图片资源时，必须说明来源、授权状态和是否可再分发。
- 提交前运行 `./scripts/test.sh` 和 `./scripts/build-app.sh`。

## 代码风格

- 遵循现有 Swift 和 SwiftUI 风格。
- UI 保持菜单栏工具的紧凑信息密度。
- 网络行为应保持低频、可缓存，并尊重网站访问控制。
- 不接受验证码绕过、反爬规避或用户跟踪代码。

## 提交信息

使用简短、命令式的提交标题，例如：

```text
Fix event grouping for pinned matches
Add date selector to schedule view
```
