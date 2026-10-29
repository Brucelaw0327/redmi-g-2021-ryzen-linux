# 驱动修复：bitland-mifs-wmi

原厂驱动在这台机器上有一个**功能性** bug，不是性能调优，是档位切换根本用不了。

## Bug A：AC 供电类型误判

驱动在 `profile_set()` 里检查电源适配器类型，遇到不认识的类型就拒绝切档：

```c
if (output.data[0] != WMI_SYSTEM_AC_CIRCULARHOLE)
        return -EOPNOTSUPP;
```

本机 EC 对 `WMI_SYSTEM_AC_STATE` 的查询返回 **0**（一个未定义的类型），于是所有档位写入都被拒。表现就是 `platform_profile` 写什么都不生效。

修法：只在明确报告 Type-C 供电时拒绝，未定义值放行 —— 因为档位本来就是由 EC 自己管的，跟适配器类型没有必然关系。

```c
if (output.data[0] == WMI_SYSTEM_AC_TYPEC) {
        dev_info(data->dev, "performance mode unavailable on Type-C power\n");
        return -EOPNOTSUPP;
}
```

## Bug B：`balanced` 假成功

ACPI 导出的 `platform_profile_choices` 含 `balanced`，但固件的均衡档实际叫 `balanced-performance`。写 `balanced` 驱动照收不误，固件默默忽略，回读还是旧值 —— 调用方以为成功了。

修法：均衡档统一映射到 `balanced-performance`。

## 安装

```bash
sudo ./install.sh
sudo reboot
```

脚本分 6 步：

1. 校验依赖（`dkms`、`/lib/modules/$(uname -r)/build`）
2. 备份原始 `.ko` 到 `/root/bitland-bak/orig-<kernel>.ko.zst`
3. 装源码到 `/usr/src/bitland-mifs-wmi-1.1/`
4. `dkms add/build/install --force` + `depmod`
5. `modprobe -r` / `modprobe` 热替换（模块被占用则失败，重启即可）
6. 逐档写测：`low-power` / `balanced-performance` / `performance` 各写一次，打印回读值与固件 0x230，最后恢复均衡档

第 6 步就是判断补丁是否生效的地方 —— 如果 `performance` 那行回读还是旧值，说明模块没换成功。

**为什么用 DKMS**：不走 DKMS 的话，每次内核升级都会退回原厂有 bug 的版本，档位又不工作了。DKMS 会在新内核安装时自动重编。

## 验证

```bash
dkms status | grep bitland           # bitland-mifs-wmi/1.1, <kernel>, x86_64: installed
modinfo bitland_mifs_wmi | grep filename
# 期望 /lib/modules/<kernel>/updates/dkms/bitland-mifs-wmi.ko.zst
# 若是 /lib/modules/<kernel>/kernel/drivers/... 说明还在用原版

cat /sys/firmware/acpi/platform_profile_choices
```

Bug A 修好后，切档会立刻生效；用 `../tools/perfmode.sh show` 看固件侧真实档位确认。

## 卸载

```bash
sudo ./uninstall.sh
```

`dkms remove` + 删源码目录 + `depmod`，恢复上游原版。

## 文件

| 文件 | 说明 |
|---|---|
| `package/bitland-mifs-wmi.c` | 打过补丁的源码 |
| `package/Makefile` | Kbuild 包装 |
| `package/dkms.conf` | DKMS 配置（版本号 1.1，用来覆盖原版） |
| `upstream-original-v7.3.c` | 内核 7.3 原版，用来 diff 对照 |
| `install.sh` / `uninstall.sh` | 安装 / 卸载 |

## 上游

Bug A 是驱动层逻辑错误，受影响机型应该不止这一台。完整报告见 [`../docs/bug-report-bitland-ac-type.txt`](../docs/bug-report-bitland-ac-type.txt)，投递地址 `platform-driver-x86@vger.kernel.org`。
