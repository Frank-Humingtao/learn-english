# 调研：文章入库方式与个人使用的版权边界

对应工单：[06-article-ingestion](https://github.com/Frank-Humingtao/learn-english/blob/e948511/.scratch/english-learning-system/issues/06-article-ingestion.md)
调研日期：2026-11-11

> 声明：本文不是法律意见。版权部分只按风险高低分级，具体情况请咨询专业人士。

## 问题

外部 agent 推荐的英文文章分散在各个网页上。要让它们以统一、可读的形式进入 iPhone App（体验接近 Readwise Reader），需要回答四个问题：

1. 现成稍后读服务的 API 能不能直接用？
2. 自己抓正文（Mozilla Readability）时，存链接、存摘要、存全文分别有什么版权风险？前提是个人使用，但仓库是公开的。
3. GitHub issue 或公开仓库适合放文章内容，还是只适合放链接？
4. 推荐做法是什么？

---

## 1. 现成稍后读服务的 API

### Readwise Reader

- **鉴权**：请求头带 `Authorization: Token XXX`，token 在 readwise.io/access_token 获取。`GET https://readwise.io/api/v2/auth/` 返回 204 表示 token 有效。来源：https://readwise.io/reader_api
- **入库**：`POST https://readwise.io/api/v3/save/`
  - `url` 必填。
  - `html` 可选。不传时由 Reader 自己去抓取该 URL。
  - `should_clean_html=true` 时，Reader 会清洗传入的 HTML，并解析出标题和作者。
  - 还可以传 `title`、`author`、`summary`、`language`、`published_date`、`tags`、`notes` 等字段。
  - 新建返回 201，文档已存在返回 200。
  - 来源：https://readwise.io/reader_api
- **读取**：`GET https://readwise.io/api/v3/list/` 默认不返回正文。加 `withHtmlContent=true` 后，每篇会带 `html_content` 字段。支持 `updatedAfter`、`tag`、`location` 等过滤，用 `pageCursor` 分页，每页最多 100 条。来源：https://readwise.io/reader_api
- **限流**（按 token 计）：save 50 次/分钟，list 20 次/分钟。超限返回 429 和 `Retry-After`。另有 webhook，在 `/webhook` 配置。来源：https://readwise.io/reader_api
- **费用**：没有免费档，所有方案都有 30 天试用。按年付费时：
  - "Reader Only"：$7.99/月，含 Reader 和 API。
  - "Full Readwise"：$9.99/月。
  - 学生可申请 5 折。
  - 来源：https://readwise.io/pricing
- **能不能复用**：能。外部 agent 只要调一次 `save` 传入 URL，Reader 就会完成抓取、清洗和存储。App 用 `list?withHtmlContent=true&updatedAfter=…` 增量拉取正文即可。全文存在 Readwise 的私有账户里，不进公开仓库。
- **代价**：
  - 每月订阅费。
  - 依赖第三方服务。
  - 对中国大陆网络的可用性本次没有验证（见“新的开放问题”）。

### Instapaper

- Instapaper 官方文档 https://www.instapaper.com/api/full 本次无法抓取到正文。以下信息来自第三方客户端的 README，可信度低一级：
  - Full API 只对付费订阅用户开放。
  - 需要先申请 consumer key/secret。
  - 只支持 xAuth，也就是用用户名和密码换取 token。
  - `bookmarks/get_text` 可以取回正文。
  - 来源：https://github.com/stve/instapaper
- **结论**：门槛是订阅、人工审批 key，外加 xAuth 需要交出账户密码。相比 Readwise 没有任何优势，不推荐。

### Wallabag（开源，可自托管）

- **鉴权**：OAuth2。先在 Web 界面 `/developer/client/create` 创建 client，再用 `grant_type=password` 换取 access_token。access_token 有效期 3600 秒，响应里同时带 refresh_token。来源：https://doc.wallabag.org/developer/api/oauth/
- **入库**：`POST /api/entries`，参数有 `url`、`title`、`content`、`tags`、`language`、`published_at`、`authors`、`origin_url` 等。源码注释说明，只要同时提供非空的 `content`、`title` 和 `url`，Wallabag 就不再自己抓取。来源：https://github.com/wallabag/wallabag/blob/master/src/Controller/Api/EntryRestController.php
- **读取**：`GET /api/entries.json` 分页返回条目，条目对象里包含 HTML 格式的 `content` 字段。来源：https://doc.wallabag.org/developer/api/methods/
- **结论**：功能上可以复用。但需要自托管服务器，或者订阅 wallabag.it 托管服务。对单人系统来说偏重，不如直接在设备端解析。

---

## 2. 自己抓取正文：Mozilla Readability

- **是什么**：Firefox 阅读视图使用的正文提取库的独立版本。npm 包名 `@mozilla/readability`，许可证 Apache-2.0。来源：https://github.com/mozilla/readability
- **输出**：`parse()` 返回 `title`、`content`（HTML）、`textContent`（纯文本）、`length`、`excerpt`、`byline`、`dir`、`siteName`、`lang`、`publishedTime`。来源同上。
- **判断能否解析**：`isProbablyReaderable()` 可以快速粗判一个页面能否提取出正文，但存在误判。来源同上。
- **安全**：
  - Readability 不清洗输出。处理不可信输入时，需要再过一遍 DOMPurify 之类的 sanitizer，并配合 CSP。
  - 在 Node 环境下要用 jsdom，并保持 jsdom 默认禁用脚本执行和远程资源加载。
  - 来源同上。
- **对本系统的意义**：
  - `textContent` 正好可以拿来算 Coverage。
  - `title`、`byline`、`siteName`、`excerpt`、`publishedTime` 正好构成文章的元数据。
  - 这个库是纯 JS，可以在 iOS 的 WKWebView 里运行（这是推断，本次没有做原型验证）。这样抓取和解析都发生在学习者自己的设备上。

---

## 3. 版权风险分级（个人使用 + 公开仓库）

### 法律依据

- **中国《著作权法》（2020 修正）**：
  - 第二十四条第一款列出可以“不经著作权人许可，不向其支付报酬”使用作品的情形，条件是“应当指明作者姓名或者名称、作品名称，并且不得影响该作品的正常使用，也不得不合理地损害著作权人的合法权益”。其中：
    - 第（一）项为“为个人学习、研究或者欣赏，使用他人已经发表的作品”。
    - 第（二）项为“为介绍、评论某一作品或者说明某一问题，在作品中适当引用他人已经发表的作品”。
  - 第十条第（十二）项规定的信息网络传播权，是指“以有线或者无线方式向公众提供，使公众可以在其选定的时间和地点获得作品的权利”。
  - 来源：https://www.ncsti.gov.cn/zcfg/flfg/202104/t20210402_29487.html （转载全国人大公布的法律文本）
  - **要点**：个人学习这一项豁免的是个人使用。把全文放进公开仓库，就等于“向公众提供，使公众可以在其选定的时间和地点获得”，触及的正是信息网络传播权。
- **美国合理使用（17 U.S.C. §107）**：GitHub 和多数英文原站都受美国法管辖。合理使用有四个考量因素：
  1. 使用的目的与性质。非营利、教育用途有利，转换性使用也有利。
  2. 作品的性质。新闻、事实类作品比创作类作品更容易构成合理使用。
  3. 使用的数量与实质性。用得越多越不利，而且不存在“安全字数”。
  4. 对原作市场的影响。
  - 来源：https://www.copyright.gov/fair-use/
  - **要点**：公开转载全文时，第 3 项（全文照搬）和第 4 项（替代了原站的访问和订阅）对使用者都不利。
- **GitHub 条款**：
  - **ToS D.3**：用户发布并非自己创作的内容时，必须拥有发布的权利。来源：https://docs.github.com/en/site-policy/github-terms/github-terms-of-service
  - **ToS D.5**：仓库一旦公开，即视为允许其他用户通过 GitHub 查看、复制和 fork。来源同上。
  - **可接受使用政策第 3 节**：禁止侵犯他人版权的内容。来源：https://docs.github.com/en/site-policy/acceptable-use-policies/github-acceptable-use-policies
  - **DMCA 流程**：
    - 收到通知后，GitHub 会公开一份脱敏副本。
    - 如果只有部分内容侵权，用户约有 1 个工作日修改；如果整个仓库被指侵权，会被直接禁用。
    - 屡次侵权可能导致账户被终止。
    - 合理使用主要由权利人自行判断，GitHub 只审核通知的形式要件。
    - 来源：https://docs.github.com/en/site-policy/content-removal-policies/dmca-takedown-policy

### 风险分级

| 存储内容 | 存放位置 | 风险 | 理由 |
|---|---|---|---|
| 链接 + 元数据（标题、作者、站点、日期、字数） | 公开仓库 / issue | **低** | 不复制作品表达。注明作者和来源也符合第二十四条“指明作者、作品名称”的精神。 |
| 派生统计（Coverage、生词表、词频，不含连续原文） | 公开仓库 | **低** | 只是关于作品的数据，不能替代原文阅读。 |
| 自写摘要 / 推荐理由（agent 用自己的话写） | 公开仓库 | **低** | 属于新的表达，不是复制原文。 |
| 原文短引用（一两句，用于说明某个词的语境） | 公开仓库 | **低～中** | 接近“适当引用”和合理使用第 3 项。量要小，并且注明出处。 |
| 原站的 `excerpt`、导语段原样保存 | 公开仓库 | **中** | 整段照搬，“适当”与否取决于篇幅，没有安全线。 |
| 全文（Readability 提取的 HTML 或文本） | **公开**仓库 / issue | **高** | 属于向公众提供，可能被 fork 而扩散，替代原站流量。可能遭遇 DMCA 禁用仓库，累犯会危及账户。 |
| 全文 | 学习者设备本地缓存 / Readwise 等私有账户 | **低** | 典型的个人学习使用，不向公众提供。 |
| 全文 | GitHub **私有**仓库 | **低～中** | 不向公众提供，但仍需满足 D.3 的发布权利要求，而且失去了“仓库公开”这一前提。 |
| 公有领域或 CC 许可文章（如 CC BY）的全文 | 公开仓库 | **低** | 按许可条件署名即可。前提是逐篇确认许可证。 |

---

## 4. GitHub issue 或公开仓库该放什么

- **只放链接 + 元数据 + 派生数据**。这与 Progress Report 的定位一致：它是给外部 agent 读的公开快照，而不是内容库。
- **不放第三方全文**。理由有两点：
  - 法律风险最高（见上表）。
  - DMCA 处置可能连带禁用承载学习者数据的整个仓库，甚至影响账户。
- **例外**：明确为公有领域或 CC 许可的文章，可以附全文并署名，但需要逐篇确认许可证。

---

## 推荐

1. **分离“推荐”与“内容”**
   - 外部 agent 写入公开仓库的“文章推荐”只包含：`url`、`title`、`author`、`site`、`published`、`word_count`、Coverage 估计、Target 词列表、用 agent 自己的话写的推荐理由。
   - 推荐里不放原文段落。
   - 这一层风险最低。
2. **全文在设备端抓取和解析，只缓存在本地**
   - App 打开推荐时，在 WKWebView 中加载原页面，注入 `@mozilla/readability` 提取 `content` 和 `textContent`。
   - 渲染前用 DOMPurify 清洗。
   - 正文只缓存在 App 沙盒，不回写仓库。
   - 这样可以得到统一的阅读视图，且属于个人学习使用。
3. **Readwise Reader 作为可选的省事路线**
   - 如果学习者愿意付 $7.99/月：agent 调 `POST /api/v3/save` 传入 URL，App 用 `GET /api/v3/list?withHtmlContent=true` 拉取正文。抓取、清洗和跨设备同步都交给 Readwise，全文不进公开仓库。
   - 先用 30 天试用验证它在大陆网络下是否可用。
   - 不推荐 Instapaper：需要订阅和审批 key，xAuth 还要交出密码。
   - 不推荐 Wallabag：需要自托管，对单人系统偏重。
4. **Coverage 的计算基于文本，但不保存文本**
   - agent 侧或 App 侧都可以临时取得正文，算完 Coverage 只保存数字和词表。
5. **CC 或公有领域文章可以例外放全文**，前提是记录许可证字段并署名。

---

## 新的开放问题

- 在中国大陆网络下，Readwise（readwise.io）和许多英文原站（例如部分新闻站、Medium）能否稳定访问？这决定了设备端抓取是否可行，以及是否需要代理。本次未验证。
- Coverage 由谁算：外部 agent（推荐时就需要全文），还是 App（打开后再算）？如果由 agent 算，它抓取的全文需要明确“只用不存”。
- 付费墙文章（如 NYT、The Economist）用设备端 WKWebView 加载时，可以利用学习者自己的登录态，但 agent 侧拿不到正文，它的 Coverage 估计会缺失。
- Instapaper 官方文档本次未能直接读取，上文结论来自第三方客户端，需要时应再核实。
