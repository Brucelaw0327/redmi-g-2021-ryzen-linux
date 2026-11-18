# Chrome 在 NVIDIA 独显上启用视频硬解

> 机型：Redmi G 2021 锐龙版（RTX 3060 Laptop 6GB，GA106M，PCI `10de:2520`，独显直连、无 iGPU）
> 验证环境：CachyOS（Arch 系）· kernel 7.3 · KDE Plasma（Wayland）· `google-chrome-dev 160.0.8157.0`
> 关键组件：`libva-nvidia-driver 0.0.18`（VA-API over NVDEC，direct backend）

Chromium 在 Linux 上默认不开视频硬解，NVIDIA 卡更是因为官方 VA-API 不支持 NVDEC 而一直要绕路。本文记录在本机把 Chrome 的视频解码真正切到 GPU 的最小配置、验证方法和踩过的坑。

---

## 结论先行

```bash
# ~/.config/chrome-dev-flags.conf
--enable-features=VaapiOnNvidiaGPUs
```

**只要这一行**，无需 `LIBVA_DRIVER_NAME=nvidia`、无需 `--ignore-gpu-blocklist`、无需 `--use-gl=angle --use-angle=gl`。重启 Chrome 后 H.264 / VP9 / HEVC / AV1 / VP8 全部走 `VaapiVideoDecoder` 硬解。

脚本启动版（临时验证用）：

```bash
google-chrome-dev --enable-features=VaapiOnNvidiaGPUs
```

> Dev/Beta 通道的持久化配置文件是 `~/.config/chrome-dev-flags.conf`；稳定版 Google Chrome 用 `chrome-flags.conf`，Chromium 用 `chromium-flags.conf`。launcher 启动时把文件内容当命令行参数注入。

---

## 为什么能这么简单：环境已经具备的条件

这套最小配置依赖几个本机已经满足的前提，换机器前先逐条核对：

1. **VA-API 驱动已就绪且默认指向 NVDEC。** 实测 `vainfo`（不带任何环境变量）直接输出 `VA-API NVDEC driver [direct backend]`，列出 h264 / vp8 / vp9 / hevc / av1 的 `VAEntrypointVLD`：

   ```bash
   vainfo | head -5
   # VA-API version: 1.24 (libva 2.24.0)
   # Driver version: VA-API NVDEC driver [direct backend]
   ```

   关键是 **direct backend** —— 这是 `libva-nvidia-driver 0.0.18` 的新特性，它把多平面 YUV 导出成单个 dma-buf、统一用 Chromium 期望的 DRM modifier，才让 Chrome 能消费 NVIDIA 的解码输出。旧版本不行。

2. **浏览器构建带 VA-API 支持。** Arch 系的 `google-chrome-dev` 编译进了 VA-API。官方 Chrome 二进制也可以。

3. **默认渲染路径已经用上 GPU。** Chrome 的 ANGLE 默认走 OpenGL，`chrome://gpu` 里 GPU0 正确识别为 `10de:2520` / RTX 3060 Laptop / 驱动 620.70.06。所以不需要再手动指定 GL 后端。

换句话说，0.0.18 之前那套"环境变量 + 一堆 feature + blocklist"的复杂配方，本质上是在补这些缺口；本机环境把它们都补齐了，于是只剩 `VaapiOnNvidiaGPUs` 这一个开关。

---

## 最大的坑：`chrome://gpu` 会骗人

默认启动（不加任何 flag）时：

- `chrome://gpu` 的 **Video Decode 显示 `Hardware accelerated`**
- GPU0 正确识别成 RTX 3060
- 看起来一切正常

但 **"Video Acceleration Information" 里的 Decoding 列表是空的**。这个空列表才是真相——实际播放时全是软解。

所以判断硬解不能看状态摘要行，必须看 Decoding 列表，或者用脚本实测播放时的真实解码器。

---

## 实测数据

用 `tools/hwdec_test.sh` 对同一批 1920×1080 测试视频（>720p，绕过 Chromium 的分辨率门槛），两种配置对比：

**默认（无 flag）：**

| 编码 | 解码器 | platform | 结果 |
|---|---|---|---|
| H.264 | `FFmpegVideoDecoder` | false | 软解 |
| VP9 | `VpxVideoDecoder` | false | 软解 |

**加 `--enable-features=VaapiOnNvidiaGPUs`：**

| 编码 | 解码器 | platform | 结果 |
|---|---|---|---|
| H.264 | `VaapiVideoDecoder` | true | 硬解 |
| VP9 | `VaapiVideoDecoder` | true | 硬解 |
| HEVC | `VaapiVideoDecoder` | true | 硬解 |
| AV1 | `VaapiVideoDecoder` | true | 硬解 |
| VP8 | `VaapiVideoDecoder` | true | 硬解 |

所有编码都过了。值得一说的是 HEVC 和 AV1：Chromium 内核层面不提供 HEVC **软解**（FFmpeg 白名单排除），但硬解照常可用；AV1 靠 GA106 的 NVDEC 硬件 + 0.0.18 的修复也能正常工作。网上常见"Chrome Linux 只硬解 H.264/VP9"的说法在这套环境下不成立。

---

## 验证方法

### 一键脚本

```bash
cd tools
./hwdec_test.sh                                       # 全编码，当前参数
./hwdec_test.sh --enable-features=VaapiOnNvidiaGPUs   # 带启动参数
CODECS=h264,vp9 ./hwdec_test.sh ...                   # 只测指定编码
```

脚本用临时 profile，不改你的真实配置；每个编码生成测试视频、播放 6.5 秒，通过 CDP 读 `kVideoDecoderName` 和 `kIsPlatformVideoDecoder`，退出时自动清理。

### 手动验证

- `chrome://gpu` → 看 **Video Acceleration Information** 的 Decoding 列表是否非空
- 播放视频后按 F12 → More tools → Media → 看 `video_decoder` 是否为 `VaapiVideoDecoder`
- 或 `chrome://media-internals` → 选 player → 看 `video_decoder` 字段
- 配合 `nvtop` 观察播放时 NVDEC 引擎是否有负载

---

## 排查记录：其他启用方式都无效

为了确认"最小配置"真的是最小，逐个试过别的方法：

| 方法 | 结果 | 原因 |
|---|---|---|
| `chrome://flags` 里搜 Vaapi / NVIDIA | 无对应条目 | 该 feature 没注册进 `about_flags.cc`，没有 UI 开关 |
| Local State 注入 `enabled_labs_experiments: ["vaapi-on-nvidia-gpus@1"]` | 无效，仍软解 | lab experiments 只对已注册的 flag 生效 |
| 设 `LIBVA_DRIVER_NAME=nvidia` | 多余 | `vainfo` 默认已识别 NVDEC driver |
| `--ignore-gpu-blocklist` / `--use-gl=angle --use-angle=gl` | 多余 | 默认渲染路径已用上 GPU |

按 Chromium 的[配置模型](https://chromium.googlesource.com/chromium/src/+/main/docs/configuration.md)，`VaapiOnNvidiaGPUs` 是 `base::Feature`，不是 flag：用户可见的 flag 要在 `about_flags.cc` 注册，而 feature 只能靠 `--enable-features` 命令行或 Google 服务器端的 field trial 开启。所以没有"内部开关"可用——命令行（含 launcher 配置文件注入）是唯一现实途径。

---

## 常见坑

- **`chrome://gpu` 的状态摘要不可信**，只看 Decoding 列表或实测解码器。
- **低于 720p 不加速**：Chromium 86+ 桌面端的行为，测硬解必须用 ≥720p 的视频。
- **YouTube 优先 VP9/AV1**：本机已验证都硬解，不需要再装 `h264ify` 之类的扩展强制切 H.264。
- **换机器别直接抄**：最小配置成立的前提是 VA-API 驱动默认可用 + Chrome 编译带 VA-API + 默认走 GPU。先在目标机器上跑 `vainfo` 和 `tools/hwdec_test.sh` 确认。
- **单 flag 之前的复杂配方**：网上常见的 `--enable-features=AcceleratedVideoDecodeLinuxGL,VaapiOnNvidiaGPUs --ignore-gpu-blocklist --use-gl=angle --use-angle=gl` 仍能工作，只是本机不需要那几个额外项。

---

## 许可

脚本：MIT。
