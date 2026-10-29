# Redmi G 2021 锐龙版 · Linux 调教笔记

> 机型：**Redmi G 2021 锐龙版**（小米 TIMI A7S / TM2037）
> CPU：Ryzen 7 5800H　GPU：RTX 3060 Laptop 6GB（130W 满血）　内存：32GB DDR4-3200 双通道
> 验证环境：CachyOS（Arch 系）· kernel 7.3.0-4-cachyos · KDE Plasma

这台机器在 Linux 下有两个原厂驱动 bug，导致**性能档位切换是坏的**：KDE 里点「平衡」没反应，`platform_profile` 看着能写但固件不认。这个仓库是排查全过程留下的东西 —— 两个补丁 + 一套验证工具 + 完整体检数据。

如果你也是这台机器（或任何用 `bitland-mifs-wmi` 的小米/红米本），可以直接装。

---

## 先看结论

| 项目 | 状态 |
|---|---|
| 性能水平 | **正常偏上**。单核达成理论值 99%，全核 8 线程 1058.6 GFLOPS |
| 散热 | **健康**。7 分钟 16 线程满载，稳态 88.8°C，频率零衰减 |
| 独显 | **130W 满血**。Windows 里看到的 95W 是均衡档的功耗墙，不是硬件上限 |
| 性能档位 | 原厂坏 → **已修复**，KDE 三档原生可用 |

详细数据见 [`docs/硬件性能与散热体检报告.html`](docs/硬件性能与散热体检报告.html)。

---

## 这台机器只有三个档位

BIOS 里写死的，不是四个也不是两个。反编译 BIOS Setup 变量确认（`Setup` GUID `a04a27f4-df00-4d42-b552-39511302113d`，**offset 0x230**）：

| 固件档位 | 0x230 | 内核 platform_profile | governor | EPP | 频率上限 |
|---|---|---|---|---|---|
| 静谧 Silence | 2 | `low-power` | powersave | power | 3201 MHz |
| 均衡 Balance | 1 | `balanced-performance` | powersave | balance_performance | 4465 MHz |
| 极速 Turbo | 0 | `performance` | performance | performance | 4465 MHz |

### ⚠️ 三个必踩的坑

**坑 1：值序不同，混用会切错档。**

```
固件 Setup 0x230：  0=极速  1=均衡  2=静谧
驱动 WMI 值    ：  0=均衡  1=极速  2=静谧
```

两套序**不一样**。看到"写 0 变成极速"和"写 0 变成均衡"都对，取决于你读的是哪一层。判断真实状态必须读 efivarfs（`offset 4+0x230=564`，前 4 字节是属性头），不能只看 `platform_profile`。

**坑 2：`balanced` 是幽灵值。**

ACPI 声明了 `low-power balanced balanced-performance performance` 四个可选值，但固件的均衡档根本不叫 `balanced`。写 `balanced` 驱动会接受、固件会忽略，回读仍是旧值 —— 属于**假成功**。均衡档必须写 `balanced-performance`。

**坑 3：直接写 sysfs 会绕过治理层。**

如果你装了下面的 KDE 桥接服务，**不要在终端手动 `echo > platform_profile`**。那样固件档位会变，但 governor/EPP 不联动，得到一个"功耗墙变了、调频策略没变"的半生效状态，重载时手感很怪。要么用 KDE 界面，要么走 D-Bus，要么用 `tools/perfmode.sh`（它自己写全链路）。

---

## 安装

两个组件，**顺序不能反**（桥接服务依赖修复后的驱动）。

### 1. 修驱动（必须）

原厂 `bitland-mifs-wmi` 有两个 bug，都在这台机器上稳定复现：

**Bug A — AC 供电类型误判。** 驱动认为只有特定 AC 类型才允许切档，而本机 EC 报告的是一个未定义值（0），于是所有档位写入都返回 `-EOPNOTSUPP`。

```diff
- if (output.data[0] != WMI_SYSTEM_AC_CIRCULARHOLE)
+ if (output.data[0] == WMI_SYSTEM_AC_TYPEC) {
+     dev_info(data->dev, "performance mode unavailable on Type-C power\n");
      return -EOPNOTSUPP;
+ }
```

改成只拒绝明确报告 Type-C 的情况，未定义值放行。

**Bug B — `balanced` 假成功。** 见坑 2，`profile_set()` 接受了固件不认的值。补丁后均衡档统一走 `balanced-performance`。

```bash
cd driver-fix
sudo ./install.sh      # DKMS 打包，重启不丢，内核升级自动重编
sudo reboot
```

验证：

```bash
dkms status | grep bitland        # 应显示 installed
cat /sys/firmware/acpi/platform_profile_choices
```

### 2. 装 KDE 三档桥接

KDE 的档位选择器只是 `org.freedesktop.UPower.PowerProfiles` 的客户端，真正的实现在 `power-profiles-daemon`（ppd）。ppd 的"平衡"写的是 `balanced` —— 就是坑 2 那个幽灵值，所以点了没反应。

这个桥接服务顶替 ppd 占住同一个总线名，把 KDE 三档映射到本机真实三档：

```bash
cd kde-bridge
sudo ./install.sh
```

它做五件事：mask 掉 ppd（防抢总线名）→ 装二进制 → 装 systemd unit → 接管 D-Bus 激活入口（ppd 原件备份到 `/usr/local/share/redmi-profile-bridge/`）→ 启动验证。

装完 KDE 托盘、系统设置→节能、以及"循环切换电源配置文件"快捷键全部原生可用。

### 3. 验证

```bash
python3 tools/verify_roundtrip.py
```

走 D-Bus 真实调用路径逐档切换，交叉核对**六项**：总线属性 / 内核档位 / governor / EPP / 固件 0x230。三档全通才算装好：

```
D-Bus 目标     总线回读       内核档位                governor     epp                   固件     判定
power-saver    power-saver    low-power              powersave    power                 静谧(2)  ✓
balanced       balanced       balanced-performance   powersave    balance_performance   均衡(1)  ✓
performance    performance    performance            performance  performance           极速(0)  ✓
```

> 只看总线属性是不够的。总线说"切了"而固件没动，正是原厂 bug 的表现形式。

---

## 不想装服务？用命令行

`tools/perfmode.sh` 自带全链路写入 + 回读校验，不依赖 D-Bus：

```bash
sudo ./tools/perfmode.sh show       # 当前状态（含固件侧真实档位）
sudo ./tools/perfmode.sh quiet      # 静谧
sudo ./tools/perfmode.sh balanced   # 均衡
sudo ./tools/perfmode.sh turbo      # 极速
sudo ./tools/perfmode.sh kbd 2      # 键盘背光 0-3
```

装了桥接服务后它会提示冲突（ppd/桥接在管），需要时 `FORCE=1` 强写。

---

## 已知限制

| 限制 | 原因 | 应对 |
|---|---|---|
| 离电切不到极速 | 固件限制，非 bug | 插电再用极速档 |
| 静谧档最高 3201 MHz | 固件把频率封顶到 4465 的 71.7% | 重载前切回均衡以上 |
| 充电阈值不支持 | 固件没这能力，KDE 会报错 | 忽略即可，与档位无关 |
| 独显直连时待机 25W | 外接屏由 dGPU 驱动，属正常开销 | 不接外屏可省 |

---

## 目录

```
driver-fix/          驱动 bug 修复（DKMS 包 + 补丁 + 上游原件对照）
kde-bridge/          KDE 三档桥接（顶替 ppd 的 D-Bus 服务）
tools/               档位切换、逐档探测、往返验证、Fn+K 抓键
bench/               体检基准源码（FLOPS / STREAM / 键盘事件）+ 原始数据
docs/                体检报告 HTML、内核 bug 报告全文
```

`bench/` 里的是当时测这台机器用的，不装也能单独编译来测别的机器：

```bash
cd bench && make            # 或分别 gcc -O3 -march=native -ffast-math -fopenmp flops.c -o flops
./allcore.sh                # 全核浮点
./soak.sh                   # 满载烤机 + 温度曲线
./mem.sh                    # 内存带宽
./disk.sh                   # 顺序读写
./gpu_watch.sh              # 独显满载温度采样
```

---

## 卸载

```bash
cd kde-bridge && sudo ./uninstall.sh      # 先卸桥接
cd driver-fix && sudo ./uninstall.sh      # 再卸驱动，恢复上游原版
```

两个脚本都会把改动还原干净（ppd 取消 mask、D-Bus 入口还原、DKMS 移除）。

---

## 上游 bug 报告

`docs/bug-report-bitland-ac-type.txt` 是准备投给 `platform-driver-x86@vger.kernel.org` 的完整报告（英文，含复现步骤、EC 返回值、补丁 diff）。Bug A 是驱动层的逻辑错误，受影响的应该不止这一台机器。

---

## 许可

脚本与补丁：MIT。`driver-fix/upstream-original-v7.3.c` 为 Linux 内核原文件，版权归原作者，GPL-2.0。
