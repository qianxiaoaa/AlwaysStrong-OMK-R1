# AlwaysStrong-TEE（R1）

> 二次修改并重新维护：[AlwaysStrong](https://github.com/evoker0/AlwaysStrong) 的硬件密钥证明引擎换成
> **TEESimulator-RS**（[ZeyolZZZ/TEESimulator-RS-fix](https://github.com/ZeyolZZZ/TEESimulator-RS-fix) 分支），
> 其余骨架（PlayIntegrityFork、原生指纹抓取、WebUI、Action 按钮）保持不变。

**本仓库 = [AlwaysStrong](https://github.com/evoker0/AlwaysStrong) 的模块骨架
＋ [ZeyolZZZ/TEESimulator-RS-fix](https://github.com/ZeyolZZZ/TEESimulator-RS-fix) 引擎
＋ [yangyang8002/yypm](https://github.com/yangyang8002/yypm) 的 keybox 多源池。**

---

## 维护说明

原作者的分支已停止维护，本仓库由 **浅笑呐** 接手重新维护。相对上游做了三件事：

1. **换引擎**：证明引擎改用仍在维护的
   [ZeyolZZZ/TEESimulator-RS-fix](https://github.com/ZeyolZZZ/TEESimulator-RS-fix)
   （Rust 版 TEESimulator-RS 的修复分支）。其发行包布局为
   `lib/<abi>/libTEESimulator.so` + `libinject.so` + `libsupervisor.so`（可选 `libcertgen.so`）
   + `classes.dex` + `keybox.xml`，模块通过 `attest/tee.sh` 适配层接入。
2. **换 keybox 来源**：原来的单一镜像 `evoker.qzz.io/key` 早已被大规模吊销。现已并入
   yypm 的 **keybox 多源池**：按优先级依次尝试多个公开上游、各自解码、结构校验、
   吊销比对，全挂时回滚到本地已验签池（见下）。
3. **换品牌与支持渠道**：二改作者署名 **浅笑呐**，支持群组改为
   [t.me/AlwaysStrongR](https://t.me/AlwaysStrongR)。

---

**Unofficial AlwaysStrong build whose attestation engine is
[TEESimulator-RS](https://github.com/ZeyolZZZ/TEESimulator-RS-fix).**

把 [AlwaysStrong](https://github.com/evoker0/AlwaysStrong) 的硬件密钥证明引擎换成
TEESimulator-RS（ZeyolZZZ 修复分支），其余骨架（PlayIntegrityFork、原生指纹抓取、WebUI、
Action 按钮）保持不变。刷入即用，目标是让 Play Integrity 拿到 **STRONG**。

---

## ⚠️ 重要声明

- 本项目是**第三方非官方二改**，与 [evoker0/AlwaysStrong](https://github.com/evoker0/AlwaysStrong)、
  [ZeyolZZZ/TEESimulator-RS-fix](https://github.com/ZeyolZZZ/TEESimulator-RS-fix)、
  [Enginex0/TEESimulator-RS](https://github.com/Enginex0/TEESimulator-RS) 的作者
  **没有任何从属、赞助或背书关系**。仓库名中的 "TEE" 仅用于说明本构建所搭载的证明引擎。
- 仅供**学习、研究与自用**。因使用本模块产生的任何后果由使用者自行承担。
- 请勿用于绕过任何你无权访问的服务，或任何违反当地法律法规的用途。

---

## 与上游 AlwaysStrong 的差异

| 项目 | 上游 AlwaysStrong v1.0.4 | 本仓库 |
|---|---|---|
| 证明引擎 | TEESimulator-RS v6.0.1-307 | **TEESimulator-RS（ZeyolZZZ fix，v6.0.1-310）** |
| 引擎适配层 | `attest/tee.sh` | `attest/tee.sh`（重新编写，适配 ZeyolZZZ 布局） |
| 引擎启动 | 由上游 tee 脚本管理 | `daemon`（app_process 载 `tee_classes.dex`）+ 原生 `supervisor` |
| keybox 来源 | 单一镜像 | **多源池（yypm 合并）** |
| Play Integrity | PlayIntegrityFork v18 | PlayIntegrityFork v18（不变） |
| 指纹自动刷新 | asfetch + aswatcher | 不变 |
| WebUI / Action | 有 | 不变 |

### keybox 多源池（并入自 yypm）

`module/keybox_fetch.sh` 不再依赖单一镜像。它按优先级依次拉取下列上游，每个源用各自
的编码解出 XML，做结构校验（`keybox_check.sh`）与 Google 吊销比对
（`keybox_revoke_check.sh`，吊销名单本身也从多个镜像拉取），第一个可用者落盘：

| 源 | 编码 | 地址 |
|---|---|---|
| yurikey | 单层 base64 | `raw.githubusercontent.com/Yurii0307/yurikey/main/key` |
| integritybox | 10×base64 → hex → rot13 | `raw.githubusercontent.com/MeowDump/MeowDump/.../OptimusPrime` |
| megatron | 10×base64 → hex → rot13 | `raw.githubusercontent.com/MeowDump/MeowDump/main/Megatron` |

- 每份通过两道校验的 key 会存入本地池 `/data/adb/tricky_store/keybox_pool/`（保留最新 5 份）。
- 当全部上游不可达、全部被吊销或全部解码失败时，自动回滚到池中最新的一份可用 key。
- 可用 `KEYBOX_SOURCES` 环境变量在最前面追加自定义源，也可用 `KEYBOX_BASE_URL`
  保留旧的单源行为。

### 本次二改保留的上游修复

1. **keybox 保护**：引擎覆盖/恢复流程中先把 keybox 抢救保存，避免被无效 key 覆盖。
2. **统一配置目录**：TEESimulator-RS 的运行时状态（`keybox.xml`、`target.txt`、
   `security_patch.txt`、`hbk`、`tee_status.txt`）全部落在 `/data/adb/tricky_store`，
   与 WebUI / Action 看到的是同一份配置，无需额外镜像桥接。
3. **开机后自愈**：`service.sh` 在 `boot_completed` 后扫描 `supervisor` / `daemon`
   / `TEESimulator` / `aswatcher`，进程缺失时按存活状态重启引擎。

---

## 组件版本

| 组件 | 版本 | 上游 |
|---|---|---|
| TEESimulator-RS（ZeyolZZZ fix） | `v6.0.1-310`（Release tag `v6.0.1-305`） | [ZeyolZZZ/TEESimulator-RS-fix](https://github.com/ZeyolZZZ/TEESimulator-RS-fix/releases) |
| PlayIntegrityFork | `v18` | [osm0sis/PlayIntegrityFork](https://github.com/osm0sis/PlayIntegrityFork) |
| AlwaysStrong 骨架 | `v1.0.4` | [evoker0/AlwaysStrong](https://github.com/evoker0/AlwaysStrong) |
| keybox 多源池 | 并入自 yypm | [yangyang8002/yypm](https://github.com/yangyang8002/yypm) |
| asfetch / aswatcher | 随 AlwaysStrong v1.0.4 | 同上 |

> 上游 Release tag 与资产内版本号不同（`v6.0.1-305` tag 携带 `v6.0.1-310` 资产），
> `build.sh` 中的 `TEE_TAG` / `TEE_ASSET` 均已钉死。

---

## 环境要求

- **Root 方案**：Magisk / KernelSU / APatch
- **ABI**：TEESimulator-RS 支付 **arm64-v8a / armeabi-v7a / x86 / x86_64** 四种载荷，
  本模块全量打包；原生 `asfetch` / `aswatcher` 助手以 arm64-v8a 为准。
- **Android**：建议 Android 13+。

---

## ⛔ 冲突：不要与这些模块同时安装

| 冲突模块 | 原因 |
|---|---|
| 独立的 TEESimulator-RS / TEESimulator 模块 | 重复接管 keystore2 证明后端 |

本模块自带 `conflict_scan.sh`，检测到上述模块会禁用本模块。**请先卸载它们再刷入。**

---

## 安装

1. 在管理器里卸载已安装的其它证明引擎模块（如独立 TEESimulator-RS），**重启一次**。
2. 刷入本仓库 Release 中的 `AlwaysStrong-<version>.zip`。
3. 重启设备。
4. 重启后点模块的 **Action** 按钮查看状态，或打开 WebUI 的 Advanced 页。

---

## 验证是否生效

```sh
# 1. TEESimulator 守护是否在跑
pidof TEESimulator

# 2. 原生 supervisor / daemon 是否在跑
pidof supervisor

# 3. keystore2 是否被注入（应能看到 inject 库）
grep -i inject /proc/$(pidof keystore2)/maps

# 4. 引擎状态文件
cat /data/adb/tricky_store/tee_status.txt

# 5. 一键收集全部诊断
sh /data/adb/modules/tricky_store/collect_logs.sh
```

端到端验证建议用 **Key Attestation**（`io.github.vvb2060.keyattestation`）或
**Play Integrity API Checker**，目标为 `MEETS_STRONG_INTEGRITY`。

首次从其它引擎切换到本模块时，启动日志里可能出现一次引擎重建记录，
新密钥在之后的操作中会恢复正常。

---

## 构建

本仓库只提交**脚本与源码**，两个上游载荷在构建时下载，不纳入版本库。

```sh
./build.sh                          # 下载 TEESimulator-RS + PlayIntegrityFork 并打包
./build.sh --tee-file PATH          # 用本地 TEESimulator-RS zip，跳过下载
./build.sh --pif-file PATH          # 用本地 PlayIntegrityFork zip，跳过下载
./build.sh --clean                  # 先清掉 build/ 与 out/
```

输出：`out/AlwaysStrong-<version>.zip`

依赖：`bash`、`unzip`、`zip`、`curl`（或 `wget`）。

---

## 目录结构

```
attest/tee.sh          TEESimulator-RS 适配层，构建时被覆盖为模块内的 attest.sh
module/                模块本体（AlwaysStrong v1.0.4 骨架 + tee 适配脚本）
  ├── daemon           app_process 载 tee_classes.dex，启动 TEESimulator 应用
  ├── keybox_fetch.sh  keybox 多源池拉取 / 解码 / 校验 / 回滚
  ├── engine.sh        PlayIntegrityFork 适配层
  ├── service.sh       服务启动 / 监控 / 引擎自愈
  └── webroot/         WebUI
archive/omk/           早期 OMK 引擎适配层归档（不再参与构建）
native/                asfetch / aswatcher 源码与预编译产物
docs/ADVANCED.md       进阶说明与排障
build.sh               构建脚本
```

---

## 许可证

本仓库是合并作品，**整体以 GPL-3.0 发布**。

| 部分 | 许可证 | 文件 |
|---|---|---|
| 合并作品（本仓库） | GPL-3.0 | [LICENSE](LICENSE) |
| AlwaysStrong（evoker0 等） | GPL-3.0 | [LICENSE-GPL-3.0.txt](LICENSE-GPL-3.0.txt) |
| PlayIntegrityFork（osm0sis） | GPL-3.0 | 同上 |
| TEESimulator-RS（Enginex0 / ZeyolZZZ） | GPL-3.0 | 同上 |

完整的第三方组件清单、修改声明与免责声明见 [NOTICE.md](NOTICE.md)。

---

## 致谢

- [Enginex0/TEESimulator-RS](https://github.com/Enginex0/TEESimulator-RS) — 证明引擎原始项目
- [ZeyolZZZ/TEESimulator-RS-fix](https://github.com/ZeyolZZZ/TEESimulator-RS-fix) — 本仓库采用的引擎分支
- [yangyang8002/yypm](https://github.com/yangyang8002/yypm) — keybox 多源池
- [evoker0/AlwaysStrong](https://github.com/evoker0/AlwaysStrong) — 模块骨架、原生指纹抓取、WebUI
- [osm0sis/PlayIntegrityFork](https://github.com/osm0sis/PlayIntegrityFork) — Play Integrity 修复
- 以及 AlwaysStrong 上游致谢中列出的 JingMatrix、KOWX712 等
- **二改作者：浅笑呐**

---

交流与反馈：[t.me/AlwaysStrongR](https://t.me/AlwaysStrongR)
