import csv, html

SRC = "/home/ccc/WorkBuddy/2026-10-29-21-04-33/bench/soak.csv"
OUT = "/home/ccc/WorkBuddy/2026-10-29-21-04-33/硬件性能与散热体检报告.html"

rows = []
with open(SRC) as f:
    for r in csv.DictReader(f):
        rows.append((float(r["sec"]), float(r["tctl_c"]), float(r["avg_mhz"])))

# ---------- SVG 折线（温度 + 频率） ----------
W, H = 940, 340
L, R, T, B = 64, 92, 28, 46
PW, PH = W - L - R, H - T - B

def X(s):  return L + s / 420 * PW
def YT(t): return T + (95 - t) / 25 * PH
def YF(f): return T + (4420 - f) / 420 * PH

def path(idx):
    return " ".join(("M" if i == 0 else "L") + f"{X(r[0]):.1f},{idx(r):.1f}"
                    for i, r in enumerate(rows))

temp_d = path(lambda r: YT(r[1]))
freq_d = path(lambda r: YF(r[2]))
area_d = temp_d + f" L{X(rows[-1][0]):.1f},{T+PH} L{X(rows[0][0]):.1f},{T+PH} Z"

grid, labels = [], []
for t in range(70, 96, 5):
    y = YT(t)
    grid.append(f'<line x1="{L}" y1="{y:.1f}" x2="{L+PW}" y2="{y:.1f}" stroke="#e6e9ef" stroke-width="1"/>')
    labels.append(f'<text x="{L-10}" y="{y+4:.1f}" text-anchor="end" class="ax" fill="#e2483d">{t}°</text>')
    f = 4420 - (95 - t) / 25 * 420
    labels.append(f'<text x="{L+PW+10}" y="{y+4:.1f}" class="ax" fill="#3b6fd4">{f:.0f}M</text>')
for s in range(0, 421, 60):
    x = X(s)
    grid.append(f'<line x1="{x:.1f}" y1="{T}" x2="{x:.1f}" y2="{T+PH}" stroke="#eef1f5" stroke-width="1"/>')
    labels.append(f'<text x="{x:.1f}" y="{T+PH+20}" text-anchor="middle" class="ax" fill="#8a93a3">{s:.0f}s</text>')

mark = ""
for s, txt in ((0, "开始满载"), (126, "峰值 93.0°C"), (240, "稳态 87~90°C")):
    i = min(range(len(rows)), key=lambda k: abs(rows[k][0] - s))
    x, y = X(rows[i][0]), YT(rows[i][1])
    mark += f'<circle cx="{x:.1f}" cy="{y:.1f}" r="4.5" fill="#fff" stroke="#e2483d" stroke-width="2.5"/>'
    anchor = "start" if s < 100 else ("end" if s > 300 else "middle")
    mark += f'<text x="{x:.1f}" y="{y-12:.1f}" text-anchor="{anchor}" class="note" fill="#c8352a">{txt}</text>'

# ---------- 测试项 ----------
tests = [
    ("CPU 单核浮点吞吐", "139.8 GFLOPS", "≈141（4.4GHz 理论峰值）", "99%", "ok"),
    ("CPU 单核 7-Zip", "6,947 MIPS", "6,500 – 7,200", "正常偏上", "ok"),
    ("CPU 全核浮点吞吐", "1,058.6 GFLOPS", "950 – 1,060", "达到上限", "ok"),
    ("CPU 全核隐含频率", "4,135 MHz", "3,600 – 4,050", "优秀", "ok"),
    ("7-Zip 多线程总分", "66,434 MIPS", "60,000 – 70,000", "正常偏上", "ok"),
    ("AES-256-GCM 单线程", "5.05 GB/s", "4.5 – 5.5", "正常", "ok"),
    ("SHA-256 单线程", "2.13 GB/s", "1.9 – 2.3", "正常", "ok"),
    ("内存单线程 triad", "28 – 30 GB/s", "25 – 32", "正常", "ok"),
    ("内存 8 进程并发 triad", "42.9 GB/s", "38 – 45（双通道 3200）", "正常", "ok"),
    ("SSD 顺序写", "1.70 GB/s", "1.70（标称）", "达标", "ok"),
    ("SSD 顺序读", "1.80 GB/s", "2.10（标称）", "正常", "ok"),
    ("SSD 4K 随机读 QD1", "≈39,000 IOPS", "15,000 – 40,000", "正常", "ok"),
    ("SSD 4K 随机写 QD1", "≈29,000 IOPS", "15,000 – 35,000", "正常", "ok"),
    ("7 分钟满载稳态温度", "88.8 °C（峰 93.0）", "< 95（Tjmax 105）", "合格", "ok"),
    ("7 分钟满载频率保持", "4,117 MHz 零衰减", "不应持续下滑", "无降频", "ok"),
    ("峰值后降温速度", "93 → 78 °C / 约 60 s", "1 分钟内明显回落", "散热响应正常", "ok"),
]

tr = ""
for name, val, ref, judge, kind in tests:
    tr += (f'<tr><td>{name}</td><td class="num">{val}</td><td class="ref">{ref}</td>'
           f'<td><span class="tag {kind}">{judge}</span></td></tr>')

HTML = f"""<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>硬件性能与散热体检报告</title>
<style>
*{{box-sizing:border-box}}
body{{margin:0;background:#f4f6f9;color:#1d2330;
font-family:-apple-system,"PingFang SC","Microsoft YaHei",system-ui,sans-serif;
-webkit-font-smoothing:antialiased}}
.wrap{{max-width:1040px;margin:0 auto;padding:40px 28px 64px}}
header{{margin-bottom:28px}}
.kicker{{font-size:12.5px;letter-spacing:.14em;color:#8a93a3;text-transform:uppercase;margin-bottom:10px}}
h1{{font-size:29px;margin:0 0 10px;letter-spacing:-.4px}}
.sub{{color:#5c6675;font-size:14.5px;line-height:1.7}}
.sub code{{background:#e9edf3;padding:1px 6px;border-radius:4px;font-size:13px;color:#3b4658}}
.verdict{{display:flex;gap:14px;margin:26px 0 0;flex-wrap:wrap}}
.vcard{{flex:1 1 260px;background:#fff;border:1px solid #e4e8ee;border-radius:12px;
padding:18px 20px;position:relative;overflow:hidden}}
.vcard::before{{content:"";position:absolute;left:0;top:0;bottom:0;width:4px;background:#2f9e68}}
.vcard .lab{{font-size:12.5px;color:#8a93a3;margin-bottom:6px}}
.vcard .res{{font-size:19px;font-weight:650;color:#1f7a51;letter-spacing:-.2px}}
.vcard .det{{font-size:13px;color:#6b7686;margin-top:6px;line-height:1.6}}
section{{background:#fff;border:1px solid #e4e8ee;border-radius:12px;padding:24px 26px;margin-top:20px}}
h2{{font-size:17px;margin:0 0 4px;letter-spacing:-.2px}}
.h2sub{{font-size:13px;color:#8a93a3;margin:0 0 18px}}
table{{width:100%;border-collapse:collapse;font-size:13.5px}}
th{{text-align:left;font-weight:600;color:#6b7686;font-size:12.5px;
padding:0 12px 10px 0;border-bottom:1px solid #e4e8ee;letter-spacing:.02em}}
td{{padding:11px 12px 11px 0;border-bottom:1px solid #f1f4f8;vertical-align:top}}
tr:last-child td{{border-bottom:none}}
.num{{font-variant-numeric:tabular-nums;font-weight:600;color:#1d2330;white-space:nowrap}}
.ref{{color:#8a93a3;font-size:12.5px}}
.tag{{display:inline-block;padding:3px 9px;border-radius:20px;font-size:12px;font-weight:600;white-space:nowrap}}
.tag.ok{{background:#e8f6ee;color:#1f7a51}}
.hw{{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:2px 26px;font-size:13.5px}}
.hw div{{padding:9px 0;border-bottom:1px solid #f1f4f8;display:flex;justify-content:space-between;gap:14px}}
.hw span:first-child{{color:#8a93a3}}
.hw span:last-child{{font-weight:600;text-align:right}}
.chart{{margin:6px -4px 0}}
.ax{{font-size:11px;font-variant-numeric:tabular-nums}}
.note{{font-size:11.5px;font-weight:600}}
.legend{{display:flex;gap:22px;font-size:12.5px;color:#6b7686;margin:0 0 6px}}
.legend i{{display:inline-block;width:16px;height:2.5px;margin-right:7px;vertical-align:middle;border-radius:2px}}
ul{{margin:8px 0 0;padding-left:18px;font-size:13.5px;line-height:1.85;color:#3b4658}}
li{{margin-bottom:5px}}
li b{{color:#1d2330}}
.warn{{background:#fff8ec;border-color:#f3e2c4}}
.warn h2{{color:#a8651a}}
.vcard.amber::before{{background:#d9902c}}
.vcard.amber .res{{color:#a8651a}}
.tag.warn{{background:#fdf1dc;color:#a8651a}}
.two{{display:grid;grid-template-columns:1fr 1fr;gap:26px}}
@media (max-width:720px){{.two{{grid-template-columns:1fr}}}}
.kv{{font-size:13.5px}}
.kv div{{display:flex;justify-content:space-between;padding:9px 0;border-bottom:1px solid #f1f4f8;gap:14px}}
.kv span:first-child{{color:#8a93a3}}
.kv span:last-child{{font-weight:600;font-variant-numeric:tabular-nums}}
.foot{{margin-top:26px;font-size:12px;color:#9aa3b1;line-height:1.8;text-align:center}}
</style></head><body><div class="wrap">

<header>
  <div class="kicker">Hardware Health Report</div>
  <h1>性能与散热体检报告</h1>
  <div class="sub">
    机型 <b>Redmi G 2021 锐龙版</b>（TIMI A7S / TM2037）　·　AMD Ryzen 7 5800H　·　
    CachyOS Linux，内核 <code>7.3.0-4-cachyos</code>　·　测试时间 2026-10-29 21:05–21:40　·　全程交流供电
  </div>
  <div class="verdict">
    <div class="vcard">
      <div class="lab">性能（同型号对比）</div>
      <div class="res">优于同型号典型水平</div>
      <div class="det">单核达理论峰值 99%，全核持续 4,117 MHz，高于同类 45W 机型常见的 3.6–4.0 GHz</div>
    </div>
    <div class="vcard">
      <div class="lab">散热（同型号对比）</div>
      <div class="res">合格 · 无任何降频</div>
      <div class="det">7 分钟满载稳态 88.8 °C，距 Tjmax 105 °C 余量 16 °C，频率零衰减</div>
    </div>
    <div class="vcard">
      <div class="lab">独立显卡</div>
      <div class="res">满血 130 W · 符合规格</div>
      <div class="det">功耗墙已确认 130 W（115 W + 15 W DB），早前读到的 95 W 是模式限制所致</div>
    </div>
  </div>
</header>

<section>
  <h2>硬件配置</h2>
  <p class="h2sub">与 Redmi G 2021 出厂规格一致，未见异常替换或单通道内存</p>
  <div class="hw">
    <div><span>处理器</span><span>R7 5800H · 8C/16T</span></div>
    <div><span>内存</span><span>32 GB DDR4-3200 双通道</span></div>
    <div><span>显卡</span><span>RTX 3060 Mobile（GA106M）</span></div>
    <div><span>系统盘</span><span>KIOXIA EXCERIA G2 1TB</span></div>
    <div><span>副盘</span><span>Samsung PM991a 512GB</span></div>
    <div><span>调频策略</span><span>amd-pstate-epp · performance</span></div>
  </div>
</section>

<section>
  <h2>独立显卡</h2>
  <p class="h2sub">来自你终端里的两次 <code>nvidia-smi</code> 读数（本沙箱无 GPU 设备节点，图形负载需在本地跑）</p>
  <div class="two">
    <div>
      <div class="kv">
        <div><span>型号 / 显存</span><span>RTX 3060 Laptop · 6 GB</span></div>
        <div><span>驱动 / CUDA</span><span>615.78.08 · 13.4</span></div>
        <div><span>温度</span><span>66 °C</span></div>
        <div><span>功耗 / 上限</span><span>25 W / <b>130 W</b></span></div>
        <div><span>性能状态 / 占用</span><span>P3 · 17 %</span></div>
        <div><span>显存占用</span><span>1,774 / 6,144 MiB</span></div>
        <div><span>显示输出</span><span>外接屏经 DP-1 由 dGPU 输出，内屏已禁用</span></div>
      </div>
    </div>
    <div>
      <ul style="margin-top:0">
        <li><b>功耗墙 130 W，与官方规格完全一致</b>（115 W 基础 + 15 W Dynamic Boost），满血状态。</li>
        <li><b>21:28 那次读到 95 W，是一次性现象。</b>同一台机器 11 分钟后重新读就回到 130 W，
            说明当时受性能模式（<code>Fn + K</code>）或供电方式限制，而不是硬件锁死或 vBIOS 被刷。
            这类限制在均衡模式 / PD 供电时很常见，切回极速模式 + 原装适配器即恢复。</li>
        <li><b>66 °C / 25 W 是外接屏的代价，不是故障。</b>这台机器的 HDMI 与 miniDP 都直连独显，
            外接显示器一走这条路，输出链路就必然经过 dGPU，显存也要常驻，所以待机功耗压不到 10 W。
            想显著降低，需要在 BIOS 里恢复核显改走混合输出——但外接屏仍然绕不开独显。</li>
      </ul>
    </div>
  </div>

  <table style="margin-top:18px">
    <thead><tr><th style="width:26%">项目</th><th style="width:22%">21:28</th>
    <th style="width:26%">21:39</th><th>官方规格</th></tr></thead>
    <tbody>
      <tr><td>功耗上限</td><td class="num" style="color:#a8651a">95 W</td>
          <td class="num" style="color:#1f7a51">130 W</td><td class="ref">130 W（115 + 15）</td></tr>
      <tr><td>核心温度</td><td class="num">57 °C</td><td class="num">66 °C</td>
          <td class="ref">满载 75–87 °C 属正常</td></tr>
      <tr><td>显存占用</td><td class="num">1,367 MiB</td><td class="num">1,774 MiB</td>
          <td class="ref">6,144 MiB 总量</td></tr>
      <tr><td>判定</td><td><span class="tag warn">受限</span></td>
          <td><span class="tag ok">符合规格</span></td><td class="ref">—</td></tr>
    </tbody>
  </table>
  <p class="h2sub" style="margin:14px 0 0">
    目前仍缺的是<b>满载持续表现</b>：130 W 是上限，实际能否长期吃住要看温度。
    按这台机器的模具，双烤时典型值是 CPU 45 W + GPU 110–115 W（垫高机身可多 5 W）；若 GPU 独烤无法维持在 115 W 以上，
    才说明散热有问题。脚本见 <code>bench/gpu_watch.sh</code>，用法见文末。
  </p>
</section>

<section>
  <h2>满载温度与频率曲线</h2>
  <p class="h2sub">16 线程 FMA 满载 420 秒，每 3 秒采样一次</p>
  <div class="legend">
    <span><i style="background:#e2483d"></i>Tctl 温度（左轴）</span>
    <span><i style="background:#3b6fd4"></i>全核平均频率（右轴）</span>
  </div>
  <div class="chart">
    <svg viewBox="0 0 {W} {H}" width="100%" role="img" aria-label="满载温度与频率曲线">
      <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="#e2483d" stop-opacity=".18"/>
        <stop offset="1" stop-color="#e2483d" stop-opacity="0"/>
      </linearGradient></defs>
      {''.join(grid)}
      <path d="{area_d}" fill="url(#g)"/>
      <path d="{freq_d}" fill="none" stroke="#3b6fd4" stroke-width="1.8"
            stroke-dasharray="5 4" opacity=".85"/>
      <path d="{temp_d}" fill="none" stroke="#e2483d" stroke-width="2.4"
            stroke-linejoin="round"/>
      {mark}
      {''.join(labels)}
    </svg>
  </div>
</section>

<section>
  <h2>逐项测试结果</h2>
  <p class="h2sub">「同型号参考」为 Ryzen 7 5800H / 该级别笔记本的常见实测区间</p>
  <table>
    <thead><tr><th style="width:34%">测试项</th><th style="width:22%">实测</th>
    <th style="width:26%">同型号参考</th><th>判定</th></tr></thead>
    <tbody>{tr}</tbody>
  </table>
</section>

<section>
  <h2>Linux 下怎么替代「小米游戏盒子」</h2>
  <p class="h2sub">GamingBox 是 Windows 专用程序（WPF + 驱动，走 WMI/EC），Linux 无法运行，Wine 也不行。
     但这台机器的内核里已经有 <code>redmi_wmi</code> 与 <code>bitland_mifs_wmi</code> 两个驱动，常用的档位切换已经可以原生完成</p>
  <table>
    <thead><tr><th style="width:28%">功能</th><th style="width:36%">Linux 现状</th><th>说明</th></tr></thead>
    <tbody>
      <tr><td>性能模式（Fn + K）</td>
          <td><span class="tag ok">硬件支持</span> <code>/sys/firmware/acpi/platform_profile</code></td>
          <td class="ref">Fn + K 可切换，但本机不使用按键，改由 perfmode.sh 直接写真实档位（见后文）</td></tr>
      <tr><td>键盘背光</td>
          <td><span class="tag ok">可用</span> <code>bitland-mifs-wmi::kbd_backlight</code></td>
          <td class="ref">亮度 0–3，直接写 brightness</td></tr>
      <tr><td>风扇曲线 / 转速</td>
          <td><span class="tag warn">不可用</span></td>
          <td class="ref">驱动只暴露 fan1–3_input 且读数恒为 0，没有 pwm 接口</td></tr>
      <tr><td>独显直连切换</td>
          <td><span class="tag warn">不可用</span></td>
          <td class="ref">MUX 由 EC/BIOS 控制，Linux 无对应工具，只能在 BIOS 里改</td></tr>
      <tr><td>GPU 功耗墙</td>
          <td><span class="tag warn">不可调</span></td>
          <td class="ref">笔记本 vBIOS 锁死，<code>nvidia-smi -pl</code> 无效；当前 130 W 已是上限</td></tr>
    </tbody>
  </table>
  <p class="h2sub" style="margin:16px 0 8px">
    切换档位（<code>bench/perfmode.sh</code>）—— 与硬件一致的三档：
  </p>
  <table style="margin-bottom:16px">
    <thead><tr><th style="width:14%">档位</th><th style="width:30%">platform_profile</th><th style="width:32%">系统侧写入</th><th>说明</th></tr></thead>
    <tbody>
      <tr><td><b>静谧</b></td><td><code>low-power</code></td>
          <td><code>powersave</code> + <code>power</code></td>
          <td class="ref">最高频率硬封顶 3,201 MHz</td></tr>
      <tr><td><b>均衡</b></td><td><code>balanced-performance</code></td>
          <td><code>powersave</code> + <code>balance_performance</code></td>
          <td class="ref">放开上限，日常与游戏主力档</td></tr>
      <tr><td><b>极速</b></td><td><code>performance</code></td>
          <td><code>performance</code> + <code>performance</code></td>
          <td class="ref">满血，即体检时的状态</td></tr>
    </tbody>
  </table>

  <pre style="background:#f6f8fb;border:1px solid #e4e8ee;border-radius:8px;padding:14px 16px;font-size:13px;overflow-x:auto;margin:0 0 16px;line-height:1.7"><code>./bench/perfmode.sh quiet      # 静谧
./bench/perfmode.sh balanced   # 均衡
./bench/perfmode.sh turbo      # 极速
./bench/perfmode.sh kbd 2      # 键盘背光 0-3
./bench/perfmode.sh show       # 查看档位、频率上限、温度、独显</code></pre>

  <h3 style="font-size:15px;margin:22px 0 8px;color:#1b2432">档位只有三个，而驱动有两个 bug</h3>
  <p class="h2sub" style="margin:0 0 10px">
    把 BIOS 镜像反编译后可以确认：Setup 里只有一个「System Performance Mode」枚举项，
    位于 <code>SystemConfig</code>（UEFI 变量 <code>Setup</code>）偏移 <code>0x230</code>，取值只有三个。
    不存在第四档：
  </p>
<pre style="background:#f6f8fb;border:1px solid #e4e8ee;border-radius:8px;padding:14px 16px;font-size:13px;overflow-x:auto;margin:0 0 14px;line-height:1.7"><code>@0x2714d6 [ONE_OF] prompt='System Performance Mode'
  help='Only silence/balance two kinds of mode are
        supported in battery mode.'
    * Turbo Mode    val=0000
    * Balance Mode  val=0001   &lt;== DEFAULT
    * Silence Mode  val=0002</code></pre>

  <p class="h2sub" style="margin:0 0 12px">
    而 ACPI 声明了四个值。把 <code>bitland-mifs-wmi</code> 的 <code>profile_set()</code> 反汇编，
    再逐值写入实测，三者的对应关系如下（<code>0x230</code> 直接从 efivarfs 读出）：
  </p>

  <table>
    <thead><tr><th style="width:14%">档位</th><th style="width:26%">platform_profile</th>
      <th style="width:20%">驱动写入 EC</th><th style="width:16%">0x230</th><th>实测</th></tr></thead>
    <tbody>
      <tr><td><b>静谧</b></td><td><code>low-power</code></td><td><code>2</code></td>
          <td>2 = Silence</td><td class="ref"><span class="tag ok">正常</span></td></tr>
      <tr><td><b>均衡</b></td><td><code>balanced-performance</code></td><td><code>1</code></td>
          <td>1 = Balance</td><td class="ref"><span class="tag ok">正常</span>（修驱动后）</td></tr>
      <tr><td><b>极速</b></td><td><code>performance</code></td><td><code>3</code></td>
          <td>0 = Turbo</td><td class="ref"><span class="tag ok">正常</span>（修驱动后）</td></tr>
      <tr><td><s>平衡</s></td><td><code>balanced</code></td><td><code>0</code></td>
          <td>0 = Turbo</td>
          <td class="ref"><span class="tag warn">假成功</span> 返回 0 但固件忽略，实际落到极速</td></tr>
    </tbody>
  </table>

  <p class="h2sub" style="margin:14px 0 10px">
    排查过程中定位到驱动里两个独立的问题，都已在本地修掉：
  </p>
  <table>
    <thead><tr><th style="width:26%">问题</th><th style="width:34%">证据</th><th>后果</th></tr></thead>
    <tbody>
      <tr><td><b>AC 类型检查误判</b><br>
              <span class="ref">bitland_check_performance_capability()</span></td>
          <td class="ref"><code>CAP: system_supplied=1</code><br>
              <code>CAP: AC type raw=0 (typec=1 circular=2)</code><br>
              驱动要求必须等于 2，EC 返回 0（枚举外的值）</td>
          <td class="ref"><code>balanced-performance</code> 与 <code>performance</code>
              一律返回 <code>-EOPNOTSUPP</code>，四选一里只有静谧真的能用</td></tr>
      <tr><td><b>mode 0 固件无实现</b></td>
          <td class="ref"><code>SET: option=3 -&gt; wmi mode=0</code> / <code>SET: ret=0</code><br>
              紧接着 <code>GET: raw mode=3</code></td>
          <td class="ref">写 <code>balanced</code> 看着成功，实际进的是极速 —— 
              这就是 KDE「平衡」档点了没反应、甚至更费电的原因</td></tr>
    </tbody>
  </table>

  <p class="h2sub" style="margin:14px 0 8px">
    修法只改一处：只在 EC <b>明确报告 Type-C</b> 时才拒绝，未定义值放行，让固件自己决定。
    保留「USB-C 供电不给满血」的原意，同时兼容返回 0 的机型。
  </p>
<pre style="background:#f6f8fb;border:1px solid #e4e8ee;border-radius:8px;padding:14px 16px;font-size:13px;overflow-x:auto;margin:0 0 14px;line-height:1.7"><code>-	if (output.data[0] != WMI_SYSTEM_AC_CIRCULARHOLE)
+	if (output.data[0] == WMI_SYSTEM_AC_TYPEC)
 		return -EOPNOTSUPP;</code></pre>

  <p class="h2sub" style="margin:0 0 10px">
    补丁已做成 DKMS 包，重启后仍生效，内核升级会自动重编：
  </p>
<pre style="background:#f6f8fb;border:1px solid #e4e8ee;border-radius:8px;padding:14px 16px;font-size:13px;overflow-x:auto;margin:0 0 14px;line-height:1.7"><code>cd bench/driver_fix
sudo ./install_driver_fix.sh      # 备份原模块 + DKMS 编译安装 + 验证三档
sudo ./uninstall_driver_fix.sh    # 需要时还原系统自带驱动</code></pre>

  <p class="h2sub" style="margin:0 0 10px">
    修好后三个真实档位全部对齐固件（写入 → 回读 → 0x230 三处一致）：
    <code>low-power</code> → 2、<code>balanced-performance</code> → 1、<code>performance</code> → 0。
    注意两套编号顺序不同——驱动写的是 WMI 值（0=均衡/1=极速/2=静谧/3=满速），
    BIOS 的 Setup 变量是 0=极速/1=均衡/2=静谧，混用会切错档。
  </p>
</section>

<section>
  <h2>KDE 三档：已打通</h2>
  <p class="h2sub" style="margin-bottom:12px">
    Plasma 的「省电 / 平衡 / 性能」不是 KDE 自己实现的：PowerDevil 的
    <code>powerdevil_powerprofileaction.so</code> 只连 D-Bus 上的
    <code>org.freedesktop.UPower.PowerProfiles</code>，真正干活的是
    <code>power-profiles-daemon</code>。而 ppd 的中间档写的是
    <code>platform_profile = balanced</code> —— 正是那个假成功的幽灵值。
    所以即使驱动修好，直接用 ppd 依然会让「平衡」误落到极速。
  </p>
  <p class="h2sub" style="margin:0 0 12px">
    解决方式是顶替 ppd 占住同一个 D-Bus 名字，把 KDE 三档映射到本机真实三档。
    桥接服务实现了 ppd 的完整接口（<code>HoldProfile</code> / <code>ReleaseProfile</code> /
    <code>SetActionEnabled</code> 与全部属性），KDE 以为自己在跟 ppd 说话：
  </p>
<pre style="background:#f6f8fb;border:1px solid #e4e8ee;border-radius:8px;padding:14px 16px;font-size:13px;overflow-x:auto;margin:0 0 14px;line-height:1.7"><code>cd bench/kde_bridge
sudo ./install_kde_bridge.sh      # mask ppd + 安装桥接 + 接管 D-Bus 激活入口
sudo ./uninstall_kde_bridge.sh    # 还原</code></pre>

  <table>
    <thead><tr><th style="width:16%">KDE 档位</th><th style="width:26%">实际写入</th>
      <th style="width:12%">0x230</th><th>governor / EPP</th></tr></thead>
    <tbody>
      <tr><td><code>power-saver</code></td><td><code>low-power</code></td><td>2</td>
          <td class="ref"><code>powersave</code> / <code>power</code></td></tr>
      <tr><td><code>balanced</code></td><td><code>balanced-performance</code></td><td>1</td>
          <td class="ref"><code>powersave</code> / <code>balance_performance</code></td></tr>
      <tr><td><code>performance</code></td><td><code>performance</code></td><td>0</td>
          <td class="ref"><code>performance</code> / <code>performance</code></td></tr>
    </tbody>
  </table>

  <p class="h2sub" style="margin:14px 0 0">
    三档已逐档实测通过，链路是 KDE → D-Bus → 桥接 → <code>platform_profile</code> → EC →
    固件 <code>0x230</code>，每一环都对得上。托盘、系统设置、「循环切换电源配置文件」快捷键
    全部原生可用，不需要记 Fn + K，也不需要 <code>perfmode.sh</code>。
  </p>
  <p class="h2sub" style="margin:10px 0 0">
    <b>不要直接写 <code>balanced</code></b>：无论用 <code>echo</code> 还是别的方式，
    它都会静默落到极速。要么走 KDE 三档，要么用
    <code>./bench/perfmode.sh quiet|balanced|turbo</code>（内部已映射到正确值并回读校验）。
  </p>
</section>

<section class="warn">
  <h2>需要注意的两点</h2>
  <ul>
    <li><b>CPU 此前被钉在最高频率运行（已解决）。</b>体检时调频策略与 EPP 都是
        <code>performance</code>，空载 8 核维持 4.4 GHz，空载温度就有 70–79 °C、风扇常转、离电续航偏短。
        这属于设置问题，不是散热故障。现在由 KDE 三档接管（见上一节），切到省电档时
        governor 与 EPP 一并变成 <code>powersave</code> / <code>power</code>，
        实测同负载下温度下降 16–19 °C。
        注意省电档会把最高频率硬封顶在 3,201 MHz，重载前记得切回「平衡」以上。</li>
    <li><b>独显的满载持续表现还没测。</b>130 W 是功耗上限，能否长期吃住要看温度曲线。
        在普通终端里跑 <code>bench/gpu_watch.sh 600</code> 再打开任意 3D 负载，把生成的
        <code>gpu_load.csv</code> 交回即可补全这一段——这是最后一块空白。</li>
  </ul>
</section>

<section>
  <h2>结论</h2>
  <p class="h2sub" style="margin-bottom:10px">
    CPU、内存、存储的性能与散热都处在<b>正常区间，且属于偏上水平</b>，没有发现硅脂干涸、
    散热模组失效、单通道内存或供电受限等老化/故障特征。<b>独显功耗墙已确认是 130 W 满血规格，仅缺口在满载温度曲线。</b>
  </p>
  <ul>
    <li><b>性能端</b>：单核 139.8 GFLOPS 与 4.4 GHz 理论峰值 141 GFLOPS 几乎重合（达成率 99%），
        说明单核睿频能完整发挥；全核 1,058.6 GFLOPS 对应 4,135 MHz，已接近 Zen3 移动版 8 核的实际上限。</li>
    <li><b>散热端</b>：7 分钟满载后温度稳定在 87–90 °C，且全核频率全程锁在 4,117 MHz 没有下滑，
        说明散热能力足以长期吃掉满血功耗；如果散热模组衰退（积灰、硅脂老化），典型表现是
        「温度顶到 100 °C 附近 + 频率逐分钟下滑 200–400 MHz」，这台机器完全没有这个现象。</li>
    <li><b>子系统</b>：内存双通道约 43 GB/s（理论 51.2 GB/s 的 84%），SSD 顺序读写接近标称，
        4K 随机性能正常，均无异常。</li>
    <li><b>可优化</b>：峰值 93 °C 对 5800H 属于正常但不算凉快。若想让风扇更安静或温度再降 5–8 °C，
        可考虑限制 PPT（如 <code>ryzenadj --stapm-limit=45000</code>）或清灰换硅脂；
        日常轻载用 <code>perfmode.sh balanced</code> 即可，不必常驻极速档。</li>
    <li><b>独显端</b>：功耗墙上限 130 W，与官方满血规格一致；轻载 66 °C 正常。
        早前的 95 W 读数是性能模式限制，已排除硬件问题。只剩满载温度曲线待补。</li>
  </ul>
</section>

<div class="foot">
  测试方法：自编译 AVX2/FMA 吞吐程序（8 条独立依赖链饱和 2×256bit FMA 管线）、
  STREAM 风格 triad、7-Zip 内置基准、OpenSSL speed、O_DIRECT dd、k10temp 每 3 秒采样。<br>
  CPU 功耗（RAPL）与风扇转速读数在当前环境下需要 root 权限 / EC 驱动支持，未纳入本报告。<br>
  独显满载测试：<code>bench/gpu_watch.sh 600</code> —— 先启动它，再打开任意 3D 负载（游戏或 <code>gpu-burn</code>），
  600 秒后把 <code>bench/gpu_load.csv</code> 交回即可补全这一段。
</div>
</div></body></html>"""

with open(OUT, "w", encoding="utf-8") as f:
    f.write(HTML)
print("写入:", OUT, len(HTML), "字符")
