# KDE 三档桥接

让 KDE 的「省电 / 平衡 / 性能」直接驱动本机 EC 的三档。

## 为什么需要这一层

KDE 的档位选择器（电池托盘、系统设置 → 节能、"循环切换电源配置文件"快捷键）本身不碰硬件，它只是 D-Bus 上 `org.freedesktop.UPower.PowerProfiles` 的客户端。真正的实现是 `power-profiles-daemon`（ppd）。

而 ppd 有个硬编码的假设：档位就是 `power-saver` / `balanced` / `performance`，写进 `platform_profile` 的字面量也是 `balanced`。

**这台机器固件的均衡档不叫 `balanced`。** 写 `balanced` 驱动接受、固件忽略，回读还是旧值 —— 典型的假成功。这就是 KDE 里点"平衡"毫无反应的根因。（即使打完驱动补丁也一样，因为补丁只改了 `performance` 类的路径判断，没有替 ppd 纠正这个字面量。）

所以需要一个服务顶替 ppd，占住同一个总线名和对象路径，实现同一套属性，把名字换成机器真正认的：

| KDE 档位 | platform_profile | governor | EPP |
|---|---|---|---|
| `power-saver` | `low-power` | powersave | power |
| `balanced` | `balanced-performance` | powersave | balance_performance |
| `performance` | `performance` | performance | performance |

这样 KDE 侧零改动、语义与固件一致，且顺带把 governor/EPP 一起管住了 —— ppd 原本也是这么做的。

## 实现要点

- Python3 + Gio（`gi.repository.Gio`），无第三方依赖，走 GLib 主循环
- 实现 `org.freedesktop.UPower.PowerProfiles` 的 `ActiveProfile`（读写）、`Profiles`、`Actions`、`ActiveProfileHolds`，外加 `ProfileReleased` 信号
- 每 1 秒轮询 `platform_profile`，外部改动（比如 Fn+K、或别人直接写 sysfs）会同步到总线并打日志
- **写入顺序不能反**：先 `platform_profile`，再 governor，最后 EPP。`amd-pstate-epp` 在 governor 为 `performance` 时会把 EPP 可用值锁成只剩 `performance`，此时写别的值会静默失败
- 只写 `cpu0` 是不够的，遍历 `cpu*/cpufreq/*`（每个核一份）

环境变量（调试用）：

| 变量 | 作用 |
|---|---|
| `DRY_RUN=1` | 不写 sysfs，只打日志 |
| `BUS_TYPE=session` | 挂会话总线，不需要 root，也不碰系统总线 |
| `PP_PATH=/tmp/pp` | 换掉 platform_profile 路径 |
| `POLL_MS=1000` | 轮询间隔 |

## 安装

```bash
sudo ./install.sh
```

四步：

1. `systemctl mask power-profiles-daemon`（masked 后 D-Bus 也拉不起来，防抢名）
2. 装二进制到 `/usr/local/bin/`，unit 到 `/etc/systemd/system/`，`enable --now`
3. 把 `/usr/share/dbus-1/system-services/org.freedesktop.UPower.PowerProfiles.service` 指向本服务，**原件备份到 `/usr/local/share/redmi-profile-bridge/original-dbus-service`**
4. 启动并做一次端到端验证（读总线三档 + 切一轮）

## 验证

```bash
# 三档是否都在
busctl --system get-property org.freedesktop.UPower.PowerProfiles \
  /org/freedesktop/UPower/PowerProfiles \
  org.freedesktop.UPower.PowerProfiles Profiles

# 当前档位
busctl --system get-property org.freedesktop.UPower.PowerProfiles \
  /org/freedesktop/UPower/PowerProfiles \
  org.freedesktop.UPower.PowerProfiles ActiveProfile
```

完整往返验证（六项交叉核对，推荐）：

```bash
python3 ../tools/verify_roundtrip.py
```

单独测服务本身（不需要 root，用私有会话总线）：

```bash
./test.sh
```

## ⚠️ 装了就别手动写 sysfs

```bash
echo performance | sudo tee /sys/firmware/acpi/platform_profile   # ❌ 不要这样
```

这样能改掉固件档位，但**绕过本服务**，governor 和 EPP 不会跟着动。结果是"功耗墙变了、调频策略没变"的半生效状态：`platform_profile` 显示 `performance`，实际 governor 还是 `powersave`、EPP 还是 `balance_performance`，重载时频率上不去，手感很怪，还很难查。

要么用 KDE 界面，要么走 D-Bus：

```bash
busctl --system set-property org.freedesktop.UPower.PowerProfiles \
  /org/freedesktop/UPower/PowerProfiles \
  org.freedesktop.UPower.PowerProfiles ActiveProfile s performance
```

注意是 **`set-property`（属性写入）**，不是方法调用 —— 这个接口没有 `SetActiveProfile` 方法，用 `busctl call` 会报 `No such method`。

## 卸载

```bash
sudo ./uninstall.sh
```

停服务 → 删二进制和 unit → 还原 D-Bus 激活文件 → `unmask` ppd → 启用 ppd。

## 文件

| 文件 | 说明 |
|---|---|
| `redmi-profile-bridge` | 服务主体 |
| `redmi-profile-bridge.service` | systemd unit（`Type=dbus`，`Restart=on-failure`，与 ppd 互斥） |
| `install.sh` / `uninstall.sh` | 安装 / 卸载 |
| `test.sh` | 8 个环节的端到端验证，跑在私有会话总线上，靠看回读值判断 |
