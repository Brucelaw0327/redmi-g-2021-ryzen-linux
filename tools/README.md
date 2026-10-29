# 工具

| 脚本 | 用途 | 需要 root |
|---|---|---|
| `perfmode.sh` | 命令行切三档 + 看状态（含固件侧真实档位） | 是 |
| `probe_profiles.sh` | 逐档写测：每档的频率上限 / 负载峰值 / 末温 / 固件 0x230 | 是 |
| `verify_roundtrip.py` | **验收用**。走 D-Bus 逐档切换，六项交叉核对 | 否 |
| `watch_fnkey.sh` | 抓 Fn+K 按键与档位切换日志，排查快捷键 | 视情况 |
| `profile_sync.sh` | 守护进程：Fn+K 改了 EC 档位后自动补写 governor/EPP | 是 |
| `install_profile_sync.sh` | 把上一个装成 systemd 服务 | 是 |

## 日常最常用

```bash
sudo ./perfmode.sh show        # 现在什么档
sudo ./perfmode.sh turbo       # 切极速
python3 ./verify_roundtrip.py  # 确认三档真的都在工作
```

## ⚠️ `profile_sync.sh` 和 `kde-bridge` 二选一

两个都在干同一件事：轮询 `platform_profile`，变了就补写 governor/EPP。

- **用 KDE 界面切档** → 装 `../kde-bridge/`，**不要**装 `profile_sync.sh`。两者同时跑会互相覆盖，档位反复横跳。
- **不装桥接、只按 Fn+K 切档** → 装 `profile_sync.sh`，它负责把 Fn+K 的 EC 变化同步到 CPU 策略。

Fn+K 本身只改 EC 层（`platform_profile`），**不会动 governor 和 EPP**。所以只按 Fn+K 不装 profile_sync 的话，会出现"EC 已经在静谧档、但 CPU 还被 performance 策略钉着高频"的状态 —— 风扇不降，温度不降。这就是 profile_sync 存在的理由。

```bash
sudo ./install_profile_sync.sh           # 安装并启动
sudo ./install_profile_sync.sh remove    # 卸载
```

## `verify_roundtrip.py` 为什么这么写

判断档位是否真的切换，**只看 `platform_profile` 是不够的** —— 原厂 bug 的表现就是"写进去了、读出来也对、但固件没动"。所以脚本同时核对六项：

总线 `ActiveProfile` / 内核 `platform_profile` / `governor` / `EPP` / 固件 `0x230` / 调用返回值

还有一个陷阱：必须通过 **D-Bus 属性写入**（`busctl set-property`）来切，不能用 `echo >` 直接写 sysfs。直接写会绕过桥接服务，导致 governor/EPP 不联动。这个接口也**没有 `SetActiveProfile` 方法**，用 `busctl call` 会报 `No such method`。
