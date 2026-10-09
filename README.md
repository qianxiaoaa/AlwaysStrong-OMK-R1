# AlwaysStrong-OMK（R1）

> 二次修改并重新维护：[AlwaysStrong](https://github.com/evoker0/AlwaysStrong) 的硬件密钥证明引擎换成
> **OhMyKeymint**（ITxiao6666 分支），其余骨架（PlayIntegrityFork、原生指纹抓取、WebUI、Action 按钮）保持不变。

**本仓库 = [UtMostUR/AlwaysStrong-OMK](https://github.com/UtMostUR/AlwaysStrong-OMK) 的模块骨架
＋ [ITxiao6666/OhMyKeymint](https://github.com/ITxiao6666/OhMyKeymint) 引擎
＋ [yangyang8002/yypm](https://github.com/yangyang8002/yypm) 的 keybox 多源池。**

---

## 维护说明

原作者的第二改分支已停止维护，本仓库由 **浅笑呐** 接手重新维护。相对上游做了三件事：

1. **换引擎**：证明引擎从已停止维护的官方 `OhMyKeymint 1.2.0-preview-a1f3241`
   换成仍在更新的 [ITxiao6666/OhMyKeymint](https://github.com/ITxiao6666/OhMyKeymint)
   分支（当前 `1.3.5`）。二者的发行包布局一致（`libs/<abi>/{keymint,inject}` +
   `injector.toml` + `keybox.xml`），模块适配层无需改动。
2. **换 keybox 来源**：原来的单一镜像 `evoker.qzz.io/key` 早已被大规模吊销。现已并入
   yypm 的 **keybox 多源池**：按优先级依次尝试多个公开上游、各自解码、结构校验、
   吊销比对，全挂时回滚到本地已验签池（见下）。
3. **换品牌与支持渠道**：二改作者署名 **浅笑呐**，支持群组改为
   [t.me/AlwaysStrongR](https://t.me/AlwaysStrongR)。

---

**Unofficial AlwaysStrong build whose attestation engine is
[OhMyKeymint](https://github.com/ITxiao6666/OhMyKeymint) instead of TEESimulator-RS.**

把 [AlwaysStrong](https://github.com/evoker0/AlwaysStrong) 的硬件密钥证明引擎从 TEESimulator-RS
换成 OhMyKeymint，其余骨架（PlayIntegrityFork、原生指纹抓取、WebUI、Action 按钮）保持不变。
刷入即用，目标是让 Play Integrity 拿到 **STRONG**。

---

## ⚠️ 重要声明

- 本项目是**第三方非官方二改**，与 [evoker0/AlwaysStrong](https://github.com/evoker0/AlwaysStrong)、
  [qwq233/OhMyKeymint](https://github.com/qwq233/OhMyKeymint)、
  [ITxiao6666/OhMyKeymint](https://github.com/ITxiao6666/OhMyKeymint) 的作者**没有任何从属、赞助或背书关系**。
  仓库名中的 "OMK" 仅用于说明本构建所搭载的证明引擎。
- **禁止任何商业用途**（见 [LICENSE-OhMyKeymint.txt](LICENSE-OhMyKeymint.txt) 第 1 条）。
- 仅供**学习、研究与自用**。因使用本模块产生的任何后果由使用者自行承担。
- 请勿用于绕过任何你无权访问的服务，或任何违反当地法律法规的用途。

---

## 与上游 AlwaysStrong 的差异

| 项目 | 上游 AlwaysStrong v1.0.4 | 本仓库 |
|---|---|---|
| 证明引擎 | TEESimulator-RS v6.0.1-307 | **OhMyKeymint（ITxiao6666 1.3.5 分支）** |
| 引擎适配层 | `attest/tee.sh` | `attest/omk.sh` |
| 引擎守护 | 无（引擎自管） | `omk-daemon` + `omk-injector` |
| 早期初始化 | 无 | `omk-early.sh`（post-fs-data 阶段） |
| 配置桥接 | 无 | `omk-sync.sh`（镜像到 `/data/adb/tricky_store`） |
| keybox 来源 | 单一镜像 | **多源池（yypm 合并）** |
| Play Integrity | PlayIntegrityFork v18 | PlayIntegrityFork v18（不变） |
| 指纹自动刷新 | asfetch + aswatcher | 不变 |
| WebUI / Action | 有 | 不变 |

### keybox 多源池（并入自 yypm）

`module/keybox_fetch.sh` 不再依赖单一镜像。它按优先级依次拉取下列上游，每个源用各自
的编码解出 XML，做结构校验（`keybox_check.sh`）与 Google 吊销比对
（`keybox_revoke_check.sh`，吊销名单本身也从多个镜像拉取），第一个可用者落盘：

<!-- YYPM_SOURCES_TABLE -->
| 源 | 编码 | 地址 |
|---|---|---|
| yurikey | 单层 base64 | `raw.githubusercontent.com/Yurii0307/yurikey/main/key` |
| integritybox | 10×base64 → hex → rot13 | `raw.githubusercontent.com/MeowDump/MeowDump/refs/heads/main/NullVoid/OptimusPrime` |
| megatron | 10×base64 → hex → rot13 | `raw.githubusercontent.com/MeowDump/MeowDump/main/Megatron` |
<!-- /YYPM_SOURCES_TABLE -->

- 每份通过两道校验的 key 会存入本地池 `/data/adb/tricky_store/keybox_pool/`（保留最新 5 份）。
- 当全部上游不可达、全部被吊销或全部解码失败时，自动回滚到池中最新的一份可用 key。
- 可用 `KEYBOX_SOURCES` 环境变量在最前面追加自定义源，也可用 `KEYBOX_BASE_URL`
  保留旧的单源行为。
- yypm 的目录型源（KeyboxHub / KeyboxStatus）不导入设备端：设备上没有 GitHub contents API。

### 本次二改保留的上游修复

1. **Android 17 / SDK 37 链接错误**：`omk-daemon` 调整 `LD_LIBRARY_PATH`，把 APEX 运行时目录
   排在 `/system/lib64`、`/vendor/lib64` 之前，优先加载与 keymint 匹配的 libc++。

2. **私有存储无法解密导致的无限重启**：`omk-daemon` 双门控自愈（60 秒内非请求快速退出 ≥ 2 次
   且 `keymint.log` 出现密钥材料失败签名）时重建 `/data/misc/keystore/omk/data`。

3. **错过 RPC 窗口导致注入失败**：`attest.sh` 的 `attest_ensure_injection()` 通过 `rpc.sock`
   时间戳与 `injector.log` 判定并补注入（15 分钟冷却）。

4. **keybox 保护**：引擎覆盖/恢复流程中先把 keybox 抢救到 `/data/adb/omk/guard.keybox.xml`。

---

## 组件版本

| 组件 | 版本 | 上游 |
|---|---|---|
| OhMyKeymint | `1.3.5-203-d879fb7` | [ITxiao6666/OhMyKeymint](https://github.com/ITxiao6666/OhMyKeymint/releases) |
| PlayIntegrityFork | `v18` | [osm0sis/PlayIntegrityFork](https://github.com/osm0sis/PlayIntegrityFork) |
| AlwaysStrong 骨架 | `v1.0.4` | [evoker0/AlwaysStrong](https://github.com/evoker0/AlwaysStrong) |
| keybox 多源池 | 并入自 yypm | [yangyang8002/yypm](https://github.com/yangyang8002/yypm) |
| asfetch / aswatcher | 随 AlwaysStrong v1.0.4 | 同上 |

> `1.3.5` 是第三方分支版本，**不是** OhMyKeymint 官方版本；本仓库使用 ITxiao6666 分支。

---

## 环境要求

- **Root 方案**：Magisk / KernelSU / APatch
- **ABI**：仅 **arm64-v8a**。OhMyKeymint 上游只提供 arm64-v8a 载荷，
  其他 ABI 上 `attest/omk.sh` 会直接中止安装。
- **Android**：建议 Android 13+；Android 17（SDK 37）已修复链接问题。

---

## ⛔ 冲突：不要与这些模块同时安装

| 冲突模块 | 原因 |
|---|---|
| 独立的 OhMyKeymint 模块 | 重复提供 keymint / inject |

本模块自带 `conflict_scan.sh`，检测到上述模块会禁用本模块。**请先卸载它们再刷入。**

---

## 安装

1. 在管理器里卸载已安装的「OhMyKeymint」独立模块，**重启一次**。
2. 刷入本仓库 Release 中的 `AlwaysStrong-<version>.zip`。
3. 重启设备。
4. 重启后点模块的 **Action** 按钮查看状态，或打开 WebUI 的 Advanced 页。

---

## 验证是否生效

```sh
# 1. keymint 是否在跑（应该有两个 pid：服务端 + 守护）
pidof keymint

# 2. OMK 的 RPC 套接字是否就绪
ls -l /data/misc/keystore/omk/rpc.sock

# 3. keystore2 是否被注入（应能看到 inject 库）
grep -i inject /proc/$(pidof keystore2)/maps

# 4. 信任配置是否生效
cat /data/adb/tricky_store/config.toml      # 关注 [trust] 段的 device_locked / verified_boot_state

# 5. 一键收集全部诊断
sh /data/adb/modules/tricky_store/collect_logs.sh
```

端到端验证建议用 **Key Attestation**（`io.github.vvb2060.keyattestation`）或
**Play Integrity API Checker**，目标为 `MEETS_STRONG_INTEGRITY`。

若第 5 步的日志里出现 `store was dropped and rebuilt this boot`，说明自愈逻辑
在本次开机触发过（通常发生在从其他 OMK 引擎切换过来的第一次开机），
旧密钥失效属预期，之后的新操作会恢复正常。

---

## 构建

本仓库只提交**脚本与源码**，两个上游载荷在构建时下载，不纳入版本库。

```sh
./build.sh                          # 下载 OhMyKeymint(ITxiao6666) + PlayIntegrityFork 并打包
./build.sh --omk-file PATH          # 用本地 OhMyKeymint zip，跳过下载
./build.sh --pif-file PATH          # 用本地 PlayIntegrityFork zip，跳过下载
./build.sh --clean                  # 先清掉 build/ 与 out/
```

输出：`out/AlwaysStrong-<version>.zip`

依赖：`bash`、`unzip`、`zip`、`curl`（或 `wget`）。

GitHub Actions 每天 **00:00（北京时间）** 检查
[ITxiao6666/OhMyKeymint](https://github.com/ITxiao6666/OhMyKeymint)、
[PlayIntegrityFork](https://github.com/osm0sis/PlayIntegrityFork) 是否有新 Release，
以及 [yangyang8002/yypm](https://github.com/yangyang8002/yypm) 的
`php-server/config.php` 源列表是否有变化。
有更新时自动递增 `-omk-rN.M`（例如 `r3.1` … `r3.9` 后到 `r4.0`）、构建并发布，
Release 标题为 `AlwaysStrong-v1.0.5-omk-rN.M`。也可在 Actions 页手动触发 `auto-upstream`。

模块每天 **02:00（北京时间）** 检查本仓库 [`update.json`](https://raw.githubusercontent.com/qianxiaoaa/AlwaysStrong-OMK-R1/main/update.json)，
有新版本则发系统通知。管理器也可通过 `module.prop` 的 `updateJson` 拉同一份清单。
关闭设备端检查：放置 `/data/adb/tricky_store/no_auto_self_update`。

---

## 目录结构

```
attest/omk.sh          OhMyKeymint 适配层，构建时被覆盖为模块内的 attest.sh
module/                模块本体（AlwaysStrong v1.0.4 骨架 + OMK 适配脚本）
  ├── omk-daemon       keymint 守护：库搜索路径、崩溃自愈、重启循环
  ├── omk-injector     注入器包装：等待 RPC、失败重试
  ├── omk-early.sh     post-fs-data 阶段：清理跨开机残留标记
  ├── omk-sync.sh      配置桥接：OMK 配置面 ←→ /data/adb/tricky_store
  ├── keybox_fetch.sh  keybox 多源池拉取 / 解码 / 校验 / 回滚
  ├── engine.sh        PlayIntegrityFork 适配层
  ├── service.sh       服务启动 / 监控 / 注入兜底
  └── webroot/         WebUI
native/                asfetch / aswatcher 源码与预编译产物
docs/ADVANCED.md       进阶说明与排障
build.sh               构建脚本
```

---

## 许可证

本仓库是合并作品，**整体以 AGPL-3.0-or-later 发布**。

| 部分 | 许可证 | 文件 |
|---|---|---|
| 合并作品（本仓库） | AGPL-3.0-or-later | [LICENSE](LICENSE) |
| AlwaysStrong（evoker0 等） | GPL-3.0 | [LICENSE-GPL-3.0.txt](LICENSE-GPL-3.0.txt) |
| PlayIntegrityFork（osm0sis） | GPL-3.0 | 同上 |
| OhMyKeymint（qwq233 / ITxiao6666） | AGPL-3.0 + 附加条款 | [LICENSE-OhMyKeymint.txt](LICENSE-OhMyKeymint.txt) |

GPL-3.0 与 AGPL-3.0 兼容（AGPL §13），因此合并分发时整体适用 AGPL-3.0。
完整的第三方组件清单、修改声明与免责声明见 [NOTICE.md](NOTICE.md)。

---

## 致谢

- [qwq233/OhMyKeymint](https://github.com/qwq233/OhMyKeymint) — 证明引擎原始项目
- [ITxiao6666/OhMyKeymint](https://github.com/ITxiao6666/OhMyKeymint) — 本仓库采用的引擎分支
- [yangyang8002/yypm](https://github.com/yangyang8002/yypm) — keybox 多源池
- [evoker0/AlwaysStrong](https://github.com/evoker0/AlwaysStrong) — 模块骨架、原生指纹抓取、WebUI
- [UtMostUR/AlwaysStrong-OMK](https://github.com/UtMostUR/AlwaysStrong-OMK) — 本仓库的上游二改
- [osm0sis/PlayIntegrityFork](https://github.com/osm0sis/PlayIntegrityFork) — Play Integrity 修复
- 以及 AlwaysStrong 上游致谢中列出的 JingMatrix、Enginex0、KOWX712 等
- **二改作者：浅笑呐**

---

交流与反馈：[t.me/AlwaysStrongR](https://t.me/AlwaysStrongR)
