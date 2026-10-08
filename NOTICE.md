# NOTICE — 第三方组件、修改声明与免责声明

本仓库（`AlwaysStrong-TEE`）是第三方非官方二改项目，由 **浅笑呐** 二次修改并重新维护。以下内容依据
GPL-3.0 §5 的「标明修改」义务编写。

---

## 1. 组件清单

| 组件 | 版本 | 著作权人 | 许可证 | 上游 |
|---|---|---|---|---|
| TEESimulator-RS（ZeyolZZZ fix） | `v6.0.1-310`（tag `v6.0.1-305`） | Enginex0、ZeyolZZZ 及贡献者 | GPL-3.0 | https://github.com/ZeyolZZZ/TEESimulator-RS-fix |
| AlwaysStrong | `v1.0.4` | Evokerr (evoker0) 及贡献者 | GPL-3.0 | https://github.com/evoker0/AlwaysStrong |
| PlayIntegrityFork | `v18` | osm0sis 及贡献者 | GPL-3.0 | https://github.com/osm0sis/PlayIntegrityFork |
| yypm（keybox 多源池） | 并入 | yangyang8002 及贡献者 | 见其仓库 | https://github.com/yangyang8002/yypm |

许可证全文：

- GPL-3.0（本合并作品的许可证）：[`LICENSE`](LICENSE)
- GPL-3.0（AlwaysStrong / PlayIntegrityFork / TEESimulator-RS）：[`LICENSE-GPL-3.0.txt`](LICENSE-GPL-3.0.txt)

---

## 2. 组合作品与许可证结论

- 本发行包中的全部组件（AlwaysStrong、PlayIntegrityFork、TEESimulator-RS）均为
  **GPL-3.0**，彼此兼容。
- 因此，**本仓库整体以 GPL-3.0 发布**。
- 早期基于 OhMyKeymint（AGPL-3.0 + 附加条款）的适配层已移出构建，归档于
  `archive/omk/`，不再参与本发行包；对应的 OhMyKeymint 许可证文本一并归档于
  `archive/omk/LICENSE-OhMyKeymint.txt`。

---

## 3. 修改声明

本仓库相对上游 AlwaysStrong（`v1.0.4`）的修改（二改作者：**浅笑呐**）：

- 将证明引擎由上游 TEESimulator-RS v6.0.1-307 切换为
  **[ZeyolZZZ/TEESimulator-RS-fix](https://github.com/ZeyolZZZ/TEESimulator-RS-fix)
  分支 `v6.0.1-310`**（预编译 Release，不在本仓库内构建）。
- 重写适配层 `attest/tee.sh`（构建时覆盖为模块内的 `attest.sh`），接入
  ZeyolZZZ 布局：`lib/<abi>/{libTEESimulator,libinject,libsupervisor,libcertgen}.so`
  + `classes.dex` + `keybox.xml`；`libinject.so`/`libsupervisor.so` 在安装时重命名为
  `inject`/`supervisor`，`classes.dex` 改名为 `tee_classes.dex` 以避免与
  PlayIntegrityFork 的 `classes.dex` 冲突。
- 新增模块脚本 `daemon`（`app_process` 载入 `tee_classes.dex`，以 `TEESimulator`
  为进程名启动引擎应用）。
- 修改 `service.sh`、`customize.sh`、`conflict_scan.sh`、`collect_logs.sh`、
  `uninstall.sh`、`sepolicy.rule`、`module.prop` 等，接入 TEESimulator-RS 的安装、
  启动、状态检测与开机后自愈。
- 将 keybox 拉取由单一镜像改为 **yypm 多源池**：`module/keybox_fetch.sh` 支持
  多上游源、多编码解码、结构校验、多镜像吊销比对与本地已验签池回滚。
- 将早期 OhMyKeymint 适配层与相关脚本归档至 `archive/omk/`，保留但不参与构建。

上游文件的完整源码见各自仓库；本仓库中未修改的上游脚本保留其原始版权头。

---

## 4. 免责声明

- 本模块按「现状」提供，不附带任何明示或暗示的担保。
- 本模块会修改设备上的密钥证明行为，可能导致部分应用（尤其是银行、支付、
  风控类应用）出现异常，甚至影响设备保修状态。**请自行评估风险。**
- 请勿将本模块用于绕过你无权访问的服务，或任何违反当地法律法规的用途。
- 因使用本模块产生的一切后果，由使用者自行承担；本仓库作者不承担任何责任。

---

## 5. 无隶属关系声明

本项目为独立的第三方修改版本。**它不是** TEESimulator-RS、AlwaysStrong 或
OhMyKeymint 的官方发行版，**未获得**其作者的赞助、授权或背书。所有上游项目的
名称、标识与版权归各自作者所有。
