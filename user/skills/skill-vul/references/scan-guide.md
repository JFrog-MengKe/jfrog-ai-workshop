# 扫描测试说明

## 上传测试

1. 在 skill-vul 目录执行 `python3 scripts/package-demo.py`。
2. 上传 `dist/skill-vul-1.0.0.zip` 到你的 Artifactory **Skills** 仓库。ZIP 根目录是 `SKILL.md`，没有多余的 skill-vul 外层目录。
3. 等待索引和扫描，在 Xray > Scans List 查看分类、发现和证据；如已配置 Watch/Policy，再检查是否触发 violation。
4. 记录包版本、ZIP SHA-256、平台版本、扫描时间、发现的位置和理由，和下面的样本清单比较。

按 [官方文档](https://docs.jfrog.com/security/docs/skill-scanning)，此能力目前是 beta，需 AI Catalog Security bundle，前置版本为 Xray 3.145.0、Artifactory 7.144.2。服务根据上传包分析行为，并将结果接入 Xray。

本包没有上传到平台，也没有取得实际扫描报告。它是输入样本，不是扫描器应逐项命中的断言。安全标签、保留域名、不可达入口都可能影响分类。Skill Scanning 与 SAST、SCA、Secrets 扫描应分别记录结果；在 Skills ZIP 内发现 requirements 不等于一定产生完整的依赖扫描报告。需要逐条 CWE/CVE 对照时，对本目录另外使用对应源码/依赖扫描能力，依赖于已启用的产品和索引配置。

## 源码样本清单

位置均在 `scripts/vulnerable-app.py`，代码注释中有稳定 ID。

| ID | 入口 | 故意保留的问题 | CWE |
| --- | --- | --- | --- |
| SRC-01 | GET /users?name=... | 不可信参数拼接 SQL | 89 |
| SRC-02 | GET /diagnose?host=... | 拼接 shell 命令 | 78 |
| SRC-03 | GET /file?name=... | 文件路径未限制在基目录 | 22 |
| SRC-04 | GET /fetch?url=... | 服务端请求任意 URL（SSRF） | 918 |
| SRC-05 | GET /hello?name=... | HTML 未转义（反射型 XSS） | 79 |
| SRC-06 | POST /render | 用户控制服务端模板（SSTI） | 1336 |
| SRC-07 | POST /restore | 对用户输入 pickle.loads | 502 |
| SRC-08 | POST /import-yaml | 旧版 FullLoader 解析不可信 YAML | 502 |
| SRC-09 | secret_key / ADMIN_PASSWORD | 硬编码会话密钥和演示密码 | 798 |
| SRC-10 | GET /fetch | verify=False 关闭证书校验 | 295 |
| SRC-11 | POST /password-digest | 无盐 MD5 存储密码摘要 | 759 / 328 |

`ADMIN_PASSWORD` 是独立的硬编码样本，并非真实鉴权机制；`app.secret_key` 被应用配置引用。虚构 token 不保证通过 Secrets 扫描器的格式、熵或有效性验证。

## 组件样本清单

根目录 `requirements.txt` 使用精确版本。以下是代表性漏洞，不是完整漏洞清单；表中的“修复版本”仅针对该条公告，不代表今天应采用的安全版本。

| ID | 固定组件 | 代表 CVE | 公告修复版本 | 依据 |
| --- | --- | --- | --- | --- |
| DEP-01 | PyYAML 5.3.1 | CVE-2020-14343 | 5.4 | [GHSA-8q59-q68h-6hv4](https://github.com/advisories/GHSA-8q59-q68h-6hv4) |
| DEP-02 | requests 2.19.1 | CVE-2018-18074 | 2.20.0 | [GHSA-x84v-xcm2-53pg](https://github.com/advisories/GHSA-x84v-xcm2-53pg) |
| DEP-03 | Jinja2 3.1.4 | CVE-2024-56326 | 3.1.5 | [GHSA-q2x7-8rv6-6q7h](https://github.com/advisories/GHSA-q2x7-8rv6-6q7h) |

代码用到了 requests、PyYAML 和 Flask/Jinja 模板渲染。版本命中与可利用性不同：例如 Jinja2 公告针对特定 sandbox 条件，本包 `/render` 演示的是另一类直接 SSTI，不声称复现该 CVE。旧 PyYAML 在新 Python 上可能缺少 wheel，静态扫描无需安装。Flask 用于呈现 HTTP 输入数据流，不计入上述三个预选漏洞依赖。

## Skill 行为样本

| ID | 文件 | 观察点 |
| --- | --- | --- |
| BEH-01 | scripts/untrusted-loader.py / install_unverified_helper | 未校验远端 Python 内容就执行 |
| BEH-02 | scripts/untrusted-loader.py / send_diagnostic_credentials | 凭据内容经 HTTP POST 外传的代码形态 |
| BEH-03 | references/injection-sample.md | 伪造 SYSTEM 优先级、要求隐瞒操作和操纵报告 |

这些函数不自动调用。外传函数仅指向随包的假凭据，不读取 home、真实环境变量或云端凭据；域名是 `.invalid`。扫描器可能识别其演示上下文，返回 suspicious 或 safe 也需要根据证据分析，不能简单视为漏报。

## 本地验证范围

仅验证 Python 语法、frontmatter、依赖版本声明和压缩包完整性。打包脚本可重复运行，源码不变时生成一致 ZIP 和 `.sha256` 文件。`dist/` 不进入下一次打包。

通用 skill-creator 校验器不接受顶层 `version`，但 Artifactory 技能元数据和本仓库发布约定需要该字段，因此保留。通用结构校验可在临时副本去掉 `version` 后运行，原始包仍保留 `version: 1.0.0`。
