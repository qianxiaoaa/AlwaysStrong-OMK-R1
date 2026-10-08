# AlwaysStrong-TEE — 进阶说明

本页面向想了解内部机制或自行排障的用户。普通用户看
[README](../README.md) 就够了。

---

## 1. 引擎架构

上游 AlwaysStrong 的证明引擎是可替换的：模块脚本不直接调用引擎，而是通过
一个适配层（`attest.sh`）。本仓库仍使用 `attest/tee.sh` 作为适配层，但重新编写以
接入 [ZeyolZZZ/TEESimulator-RS-fix](https://github.com/ZeyolZZZ/TEESimulator-RS-fix)
的发行布局（Rust 版 TEESimulator-RS）。

```
                 ┌──────────────────────────────┐
                 │  service.sh / customize.sh    │
                 │  （与上游完全一致的骨架）        │
                 └───────────────┬──────────────┘
                                 │ 调用
                 ┌───────────────▼──────────────┐
                 │  attest.sh  ← attest/tee.sh   │
                 │  安装 / 启动 / 存活检测           │
                 └───────────────┬──────────────┘
                                 │
                 ┌───────────────▼──────────────┐
                 │  supervisor   ./daemon        │
                 │  （托管 / 重启）+（app_process） │
                 └───────────────┬──────────────┘
                                 │
      libTEESimulator.so + libinject.so(→inject) + tee_classes.dex
      /data/adb/tricky_store  （keybox.xml / target.txt / …）
```

### 各组件职责

| 文件 | 职责 |
|---|---|
| `attest.sh`（源：`attest/tee.sh`） | 引擎适配层。安装原生载荷、启动 `supervisor`+`daemon`、进程存活检测。`attest_sync` / `attest_ensure_injection` 为 no-op。 |
| `supervisor`（源：`libsupervisor.so`） | 原生托管进程。维护 `daemon` 重启循环，并在 keystore2 重启后重新注入。 |
| `daemon`（本仓库新增） | `app_process` 载入 `tee_classes.dex`，以 `TEESimulator` 为进程名启动引擎应用。 |
| `inject`（源：`libinject.so`） | KeyMint 拦截库，注入 keystore2 进程。 |
| `libTEESimulator.so` | 模拟 TEE 的证明后端。 |
| `libcertgen.so` | 可选的本地证书链生成器（仅部分构建携带）。 |

TEESimulator-RS 自己监视 `/data/adb/tricky_store`（`keybox.xml`、`target.txt`、
`security_patch.txt`），因此不需要像早期引擎那样把配置镜像到私有运行时目录。

---

## 2. 关键路径

| 路径 | 说明 |
|---|---|
| `/data/adb/modules/tricky_store/` | 模块目录（`id` 仍为上游的 `tricky_store`） |
| `/data/adb/tricky_store/keybox.xml` | 引擎使用的 keybox |
| `/data/adb/tricky_store/target.txt` | 证明目标应用范围 |
| `/data/adb/tricky_store/security_patch.txt` | 补丁级别配置 |
| `/data/adb/tricky_store/hbk` | 设备唯一、硬件绑定的密钥种子 |
| `/data/adb/tricky_store/tee_status.txt` | 引擎写入的运行状态 |
| `/data/adb/tricky_store/persistent_keys/` | 引擎持久化的密钥 |
| `/data/adb/tricky_store/spoof.conf` | WebUI Advanced 页写入的 spoof 覆盖项 |

---

## 3. 启动时序

```
post-fs-data
  └── （引擎无早期初始化）
boot_completed 之后
  └── service.sh             扫描并清理上轮残留的 supervisor/daemon/TEESimulator
  └── attest_start           首次启动：supervisor ./daemon "$MODDIR" &
  └── aswatcher               原生 watcher 守护
  └── 每小时循环              指纹 / keybox / 补丁刷新
  └── 120s 看门狗            attest_alive 为假时重启引擎
```

TEESimulator-RS 的守护是 Java 应用，依赖完整开机的系统，因此**不在**
`post-fs-data` / `service` 阶段抢跑 keystore2，而是等到 `sys.boot_completed` 之后才启动
（`attest_early` 返回 1）。注入与崩溃恢复由原生 `supervisor` 负责。

---

## 4. 排障

### 4.1 引擎起不来

```sh
pidof TEESimulator
pidof supervisor
pidof daemon
cat /data/adb/tricky_store/tee_status.txt
```

进程全无时，先确认 ABI：模块只安装 `lib/$ABI_DIR/` 下的原生库，
若设备 ABI 与产物不符，`inject` / `supervisor` 无法加载。

### 4.2 注入失败

```sh
grep -i inject /proc/$(pidof keystore2)/maps
```

未看到 inject 时，`supervisor` 会在 keystore2 重启后自动重注入；仍失败则先看
`collect_logs.sh` 汇总的 logcat（过滤 `TEESimulator`）。

### 4.3 一键诊断

```sh
sh /data/adb/modules/tricky_store/collect_logs.sh
```

输出会覆盖：模块版本与引擎、`TEESimulator` / `supervisor` / `aswatcher` 进程状态、
引擎库清单、`hbk` / `persistent_keys` / `tee_status` 是否存在、logcat 中的
`TEESimulator` 记录，以及是否已注入 keystore2。

### 4.4 与其它引擎共存

不要与独立的 TEESimulator-RS / TEESimulator 模块同时安装：两者都接管 keystore2
证明后端会互相冲突。`conflict_scan.sh` 会在安装时与每次开机检测并禁用冲突模块。

---

## 5. 配置

`/data/adb/tricky_store/security_patch.txt` 控制证明时使用的补丁级别，
`target.txt` 控制参与证明的应用，二者由 WebUI / Action 维护，引擎直接读取。

`spoof.conf` 里的 `key=value` 会覆盖 `engine.sh` 中的 STRONG 默认值。
默认值（PlayIntegrityFork 命名）：

```
spoofProvider=0 spoofVendingFinger=<自动> spoofBuild=1 spoofProps=1 spoofSignature=0 spoofVendingSdk=0
```

`spoofVendingFinger` 在真实 SDK ≤ 32（Android 10–12L）上默认关闭，
因为在这些版本上它会破坏而非帮助 Play Integrity。

---

## 6. 构建细节

`build.sh` 做四件事：

1. 把 `module/` 复制到 `build/module/`，并把 `attest/tee.sh` 覆盖为 `attest.sh`，
   再把 `native/*/prebuilt/<abi>/` 下的 `asfetch`、`aswatcher` 放进 `bin/<abi>/`；
2. 下载并解包 TEESimulator-RS（ZeyolZZZ fix），取出
   `lib/<abi>/{libTEESimulator,libinject,libsupervisor,libcertgen}.so`、`classes.dex`、
   `keybox.xml`；`classes.dex` 改名为 `tee_classes.dex`；
3. 下载并解包 PlayIntegrityFork，取出 `classes.dex`、`zygisk/*.so` 与
   `autopif4.sh`、`killpi.sh`、`migrate.sh`、`common_setup.sh`、
   `example.pif.prop`、`app_replace_list.txt`；
4. 校验：每个被打进包的脚本都必须有对应的安装项，安装列表里的每个名字都必须
   真实存在于暂存目录，否则 `die`。

上游载荷不纳入版本库（见 `.gitignore`），以保证仓库体积可控，
同时避免再分发未经修改的第三方二进制时遗漏其许可证。

---

## 7. 上游同步

上游 AlwaysStrong 的引擎是可替换的，因此后续同步上游骨架时：

- `module/` 中与引擎无关的部分（`service.sh` 骨架、`action.sh`、`webroot/`、
  `pif_*.sh`、`native/`）可直接跟随上游；
- `attest/tee.sh` 与本仓库新增的 `daemon` 需要人工核对接口变化；
- 升级 TEESimulator-RS 版本时改 `build.sh` 顶部的 `TEE_TAG` / `TEE_ASSET`，
  并确认 `lib/<abi>/lib*.so`、`classes.dex`、`keybox.xml` 的布局未变。
