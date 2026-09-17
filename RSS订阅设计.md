# RSS 订阅技能 — 设计文档

Status: 草案（待评审）
目标版本: 1.4.0

## 1. 定位

Jarvis 不做阅读器竞品。RSS 在这里的价值是**信息摄取入口**，把「读」变成「处理掉」：

1. **未读即待办**：菜单栏角标 + 系统通知，让模块主动推给用户，而不是等用户想起来打开。
2. **喂给已有能力**：文章 → AI 总结 / 翻译 / 复制为 Markdown（复用已配好的 provider 与剪贴板历史）。
3. **本地优先**：数据落在 `JarvisJSONFile` 体系里，不依赖第三方服务；OPML 进可攻退可守。

### 已定决策

| 决策 | 选择 | 理由 |
| --- | --- | --- |
| 正文渲染 | **原生渲染**（HTML 清洗 → `AttributedString`） | 排版统一、可离线、零 WebView 能耗；不新增 HTML 注入样板 |
| 抓取与通知 | **后台定时 + 系统通知 + 菜单栏角标** | 模块存在的理由；无通知的 RSS 只是收藏夹 |
| 首版范围 | **完整 MVP** | 一次做到可用 |
| feed 解析 | **自研 XMLParser** | 零新增依赖，符合仓库现状；脏数据用 fixtures 兜住 |

## 2. 需求

### 2.1 功能需求（P0）

**订阅管理**
- 输入网站首页自动发现 feed（`<link rel="alternate" type="application/rss+xml">`）
- 输入 feed 地址直接订阅；订阅前先抓一次校验，失败不入库
- 重命名、删除、启用/停用、导出/导入 OPML
- 分组（文件夹）与按组筛选

**抓取**
- 后台定时，默认 30 分钟，可在设置中改（15 分钟 / 30 分钟 / 1 小时 / 手动）
- 条件请求：带 `ETag` / `If-Modified-Since`，304 直接跳过解析
- 连续失败指数退避（30min → 1h → 2h → 4h，上限 8h），成功即重置
- 手动刷新单个 feed / 全部

**列表与阅读**
- 筛选：全部 / 未读 / 星标；按 feed 或分组过滤；搜索（复用 `ClipboardSearchField`）
- 列表+详情骨架照 `MeetingView`；键盘 `↑↓` 切换、`空格` 展开已读、`S` 星标
- 阅读：feed 自带 content/summary 清洗后原生渲染，图片异步加载，外链跳默认浏览器
- 状态：已读/未读、星标、全部标为已读
- 打开文章自动标已读（可关）

**提醒**
- 系统通知（可配置：仅星标 feed / 静默时段 / 关闭）
- 菜单栏角标显示未读数；下拉菜单加「未读 N 篇」+「打开下一篇未读」

### 2.2 非功能需求

- **能耗**：见 §5，模块不得引入新的常驻唤醒
- **隐私**：直连抓取，不经任何代理；日志脱敏需为 RSS 定例外（见 §8）
- **容量**：每个 feed 保留最近 N 条（默认 500）与最多 90 天，超出裁剪含正文文件
- **失败可见**：抓取失败在列表行上标出并在详情页给出原因与「重试」；存盘失败横幅照 `MeetingStorageErrorBanner`

### 2.3 首版明确不做

多端同步、播客播放、readability 全文提取、规则过滤（关键词/正则）、社交分享、iCloud。

## 3. 数据模型

```
Feed   : id, title, feedURL, siteURL, groupID?, iconURL?, isEnabled,
         lastFetchedAt, lastSuccessAt, etag?, lastModified?,
         failureCount, lastError?, ttlMinutes?
Group  : id, title, order
Item   : id(去重键), feedID, title, link, author?, publishedAt,
         summaryHTML, contentHTML?, enclosureURL?, isRead, isStarred, savedAt
```

去重键优先级：`guid`/`atom:id` → 规范化 link（去 `utm_*`、去尾斜杠、统一 scheme/host 小写）→ `title + publishedAt` 哈希。

### 存储布局

`~/Library/Application Support/<dataDirectoryName>/RSS/`

```
feeds.json          订阅 + 分组（小，整份读写）
items-<feedID>.json 每个 feed 的条目索引（只存元数据 + summary）
content/<itemID>.html   按需缓存的正文字节，超出上限时按 LRU 删除
```

订阅列表照 `EntertainmentVideoDownloadHistoryStore`（`JarvisJSONFile<[Record]>` + 双 init 便于测试）；条目索引与正文旁挂文件照 `ScreenshotHistoryStore`（上限裁剪、`safeFileURL` 做路径穿越与符号链接校验）。

## 4. 架构与接线

| 新文件 | 照谁写 | 职责 |
| --- | --- | --- |
| `RSSFeed.swift` | `MeetingModels.swift` | 模型、筛选枚举、去重键规范化 |
| `RSSFeedStore.swift` | 见 §3 | 持久化 |
| `RSSFeedParser.swift` | 无先例 | XML→模型，纯函数，可单测 |
| `RSSFeedClient.swift` | `Wallpaper.swift:305-343` | protocol + 注入 session + 纯函数拼 URL + 错误枚举 |
| `RSSArticleRenderer.swift` | 无先例 | HTML 清洗 + `AttributedString` 转换 |
| `RSSRefreshScheduler.swift` | 无先例 | 周期调度、退避、低电量模式判断 |
| `AppModel+RSS.swift` | `AppModel+Meetings.swift` | 状态编排 |
| `Views/RSSContentViews.swift` | `MeetingContentViews.swift:12-124` | 列表 + 详情 |

需要改动的现存文件（穷尽 switch，漏改会编译报错）：

- `Sources/Jarvis/Skill.swift:3` 加 `case rss` + `title`/`navigationTitle`/`icon` 三处分支
- `Sources/Jarvis/AppModel.swift:39` `AppSection.navigationTitle` 加分支
- `Sources/Jarvis/Views/ContentView.swift:149` 加 `case .skill(.rss): RSSView()`
- `Sources/Jarvis/AppModel.swift` 状态 var 块加 `rssFeeds` / `rssItems` / `rssSelectedItemID` / `rssFilter` 等；`init` 里挂 store；`startDeferredStartup()`（`:317`）里首次拉取；`deinit`（`:399`）cancel 后台 Task
- `Sources/Jarvis/Views/SidebarNavigation.swift:147` `primaryRow` 扩签名支持角标
- `Sources/Jarvis/JarvisMenuBarController.swift` 加菜单项（stored property `:31`、插入顺序 `:144`、`menuWillOpen` 刷新 `:118`、`@objc` 动作 `:396`）
- `Sources/Jarvis/JarvisApp.swift:31` 内存压力回调里清 RSS 图片/正文缓存
- 快捷键（可选）：`AppModel.swift:88` var、`:177` key、`:280` manager、`AppModel+Settings.swift` 的 load/update、设置页加一行；**hotKeyID 用 10**（1=截图，2=剪贴板，3–8=窗口布局，9=会议）

## 5. 能耗设计

这是本次修复刚踩过的坑，RSS 是同类高风险模块：

- **单一调度器**：用 `NSBackgroundActivityScheduler`（系统合并唤醒、受 App Nap 约束），不是每个 feed 一个 `Timer`。项目现有唯一周期任务是剪贴板清理的 `Timer`，这里引入新做法并在注释里说明原因
- **条件请求**：304 不解析、不落盘
- **失败退避**：坏 feed 不得每 30 分钟重试一次
- **解析在后台**：utility 队列解析，主线程只做增量 UI 更新
- **低电量模式**：`ProcessInfo.isLowPowerModeEnabled` 时暂停后台刷新（可手动刷新）
- **阅读视图零 WebView**：原生渲染顺带解决 GPU 能耗；若将来引入 WebView，必须接入窗口不可见暂停（`JarvisWebPlaybackPolicy`）

## 6. 解析器要点

- 编码嗅探顺序：BOM → XML 声明 `encoding=` → HTTP `Content-Type` → UTF-8 回退
- 支持 RSS 2.0（`channel/item`、`pubDate`）与 Atom 1.0（`feed/entry`、`updated`/`published`）；`content:encoded` 命名空间取全文
- 日期解析回退链：ISO8601 → RFC 822/1123 → 常见变体（`yyyy-MM-dd HH:mm:ss`、带时区缩写）→ 放弃（记 nil，不丢条目）
- 相对链接按 `<link>`/`xml:base`/feed URL 补全为绝对
- `TestAssets/Feeds/` 放 fixtures，配 README 说明来源与授权，覆盖：正常 RSS/Atom、BOM、GBK、CDATA 嵌套、自闭合标签、命名空间前缀、非法日期、相对链接、缺 channel、`content:encoded`、超大条目

## 7. 分期

- **P0（本版本）**：§2.1 全部
- **P1**：AI 总结/翻译入口、复制为 Markdown、只显示摘要的"速览模式"、按 feed 的保留策略配置
- **P2**：规则过滤、readability 全文提取、播客 enclosure、iCloud 同步

## 8. 开放问题

1. **日志脱敏会吃掉 URL**：`JarvisLogRedactor.text` 把 URL 换成 `<url>`，抓取失败将无法定位到具体 feed。需要为 RSS 定例外（建议：记 host + 短哈希，debug 模式放行完整 URL）
2. **通知权限时机**：首次订阅成功后请求，还是设置里显式开启？（建议前者，有上下文）
3. **无角标先例**：侧边栏行组件目前不支持 badge，扩签名会影响现有调用点
4. **摘要渲染保真度**：`AttributedString` 对表格/嵌套列表支持有限，需要确定"降级成什么样"（建议：表格转成等宽文本块）

## 9. 验收标准

- 每个新文件的纯函数（解析、去重、清洗、退避计算）都有单测，fixtures 覆盖 §6 列出的脏数据
- 抓取层测试用注入的 `URLSession` + 本地 fixtures，不打真实网络
- 手测：导入 OPML（≥20 个 feed）→ 首次全量抓取 → 关窗后台等待 → 收到通知且角标正确 → 打开文章阅读 → 已读/星标/搜索/筛选正确
- 能耗手测：后台挂 30 分钟，`pmset -g assertions` 无新增断言，Activity Monitor 中 Jarvis 无持续 CPU/GPU 占用
