#!/usr/bin/env bash
# hwdec_test.sh —— 实测 Chrome/Chromium 对每个视频编码走的是硬解还是软解
#
# 原理：光看 chrome://gpu 的 "Video Decode: Hardware accelerated" 会被骗 —— 那只是
#       能力声明，不代表某个编码真的走了 GPU。本脚本对每个编码生成一个 >720p 的
#       测试视频（Chromium 86+ 桌面端低于 720p 不加速），实际播放后通过 CDP 的
#       Media.playerPropertiesChanged 读真实解码器 kVideoDecoderName。
#       VaapiVideoDecoder / kIsPlatformVideoDecoder=true 即硬解；
#       FFmpegVideoDecoder / VpxVideoDecoder 等即软解。
#
# 用法：
#   ./hwdec_test.sh                                          # 默认全编码，当前 Chrome 参数
#   ./hwdec_test.sh --enable-features=VaapiOnNvidiaGPUs      # 带启动参数
#   CHROME=google-chrome-stable ./hwdec_test.sh ...          # 换浏览器
#   CODECS=h264,vp9 ./hwdec_test.sh ...                      # 只测指定编码
#   PORT=9228 ./hwdec_test.sh ...                            # 换调试端口
#
# 依赖：ffmpeg、node（内置 fetch/WebSocket，Node 22+）、curl
# 本机实测环境：google-chrome-dev 160 + libva-nvidia-driver 0.0.18 + KDE Wayland
# 结论见 docs/chrome-nvidia-vaapi-硬解笔记.md

set -euo pipefail

PORT="${PORT:-9227}"
CODECS="${CODECS:-h264,vp9,hevc,av1,vp8}"
TMPDIR="$(mktemp -d /tmp/hwdec-test.XXXXXX)"
CHROME="${CHROME:-google-chrome-unstable}"
LOG="$TMPDIR/chrome.log"
CHROME_PID=""

cleanup() {
  [ -n "$CHROME_PID" ] && kill "$CHROME_PID" 2>/dev/null || true
  sleep 0.3
  [ -n "$CHROME_PID" ] && kill -9 "$CHROME_PID" 2>/dev/null || true
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

command -v ffmpeg >/dev/null || { echo "需要 ffmpeg"; exit 1; }
command -v node >/dev/null || { echo "需要 node (CDP 客户端)"; exit 1; }

# ---------- 1. 生成测试视频 ----------
echo "== 生成测试视频 (1920x1080, 8s) =="
FILES=()
gen() {
  local codec="$1" enc="$2" ext="$3" extra="${4:-}"
  local f="$TMPDIR/t_$codec.$ext"
  if ffmpeg -y -nostdin -f lavfi -i testsrc2=size=1920x1080:rate=30 -t 8 \
      -c:v "$enc" $extra -pix_fmt yuv420p "$f" >"$TMPDIR/ff_$codec.log" 2>&1; then
    FILES+=("$f")
    echo "  $codec: OK"
  else
    echo "  $codec: 跳过 (编码器 $enc 不可用)"
  fi
}
IFS=',' read -ra _codecs <<< "$CODECS"
for c in "${_codecs[@]}"; do
  case "$c" in
    h264) gen h264 libx264   mp4  "-preset ultrafast" ;;
    vp9)  gen vp9  libvpx-vp9 webm "-deadline realtime -cpu-used 8" ;;
    vp8)  gen vp8  libvpx     webm "-deadline realtime -cpu-used 8" ;;
    hevc) gen hevc libx265    mp4  "-preset ultrafast" ;;
    av1)  gen av1  libsvtav1  mp4  "-preset 13" || gen av1 libaom-av1 mp4 "-deadline realtime -cpu-used 8" ;;
    *) echo "  未知编码: $c" ;;
  esac
done
[ "${#FILES[@]}" -gt 0 ] || { echo "没有生成任何视频"; exit 1; }

# ---------- 2. 启动临时 Chrome ----------
OZONE=""
[ -n "${WAYLAND_DISPLAY:-}" ] && OZONE="--ozone-platform=wayland"
echo "== 启动临时 Chrome (port $PORT, 临时 profile) =="
"$CHROME" \
  --no-first-run --no-default-browser-check \
  --autoplay-policy=no-user-gesture-required \
  --user-data-dir="$TMPDIR/profile" \
  --remote-debugging-port="$PORT" \
  $OZONE "$@" about:blank >"$LOG" 2>&1 &
CHROME_PID=$!

for i in $(seq 1 50); do
  curl -sf "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1 && break
  sleep 0.2
done
curl -sf "http://127.0.0.1:$PORT/json/version" >/dev/null || { echo "Chrome/CDP 启动失败:"; tail -20 "$LOG"; exit 1; }

# ---------- 3. CDP 探针 ----------
cat >"$TMPDIR/probe.mjs" <<'EOF'
const [port, ...videos] = process.argv.slice(2);
const base = `http://127.0.0.1:${port}`;
const sleep = ms => new Promise(r => setTimeout(r, ms));
const results = [];
for (const video of videos) {
  const label = video.split('/').pop().replace(/^t_/, '').split('.')[0];
  const url = 'file://' + video;
  try {
    const t = await (await fetch(`${base}/json/new?${encodeURIComponent(url)}`, { method: 'PUT' })).json();
    const ws = new WebSocket(t.webSocketDebuggerUrl);
    let id = 0; const pending = new Map(); const props = new Map();
    ws.onmessage = e => {
      const m = JSON.parse(e.data);
      if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
      else if (m.method === 'Media.playerPropertiesChanged') {
        for (const p of (m.params?.properties || [])) props.set(p.name, p.value);
      }
    };
    await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
    const send = (method, params = {}) => new Promise(res => {
      const mid = ++id; pending.set(mid, res); ws.send(JSON.stringify({ id: mid, method, params }));
    });
    await send('Page.enable');
    await send('Media.enable');
    await sleep(6500);
    const st = await send('Runtime.evaluate', {
      expression: `(() => { const v=[...document.querySelectorAll('video')][0]; return v ? ({ct:v.currentTime,w:v.videoWidth,rs:v.readyState}) : null; })()`,
      returnByValue: true,
    });
    results.push({ label, decoder: props.get('kVideoDecoderName') || '(未捕获)', platform: props.get('kIsPlatformVideoDecoder'), state: st.result?.result?.value });
    ws.close();
    await fetch(`${base}/json/close/${t.id}`);
  } catch (e) {
    results.push({ label, decoder: 'ERROR: ' + e.message, platform: '', state: null });
  }
}
console.log('\n' + 'CODEC'.padEnd(8) + 'DECODER'.padEnd(26) + 'PLATFORM'.padEnd(10) + 'RESULT'.padEnd(8) + 'PLAYBACK');
for (const r of results) {
  const hw = String(r.platform) === 'true' && /Vaapi|Gpu|Mojo|V4L2|VideoToolbox|DXVA|D3D11/i.test(r.decoder);
  const pb = r.state ? `ct=${r.state.ct.toFixed(1)} ${r.state.w}px rs=${r.state.rs}` : 'no playback';
  console.log(r.label.padEnd(8) + String(r.decoder).padEnd(26) + String(r.platform).padEnd(10) + (hw ? 'HW' : 'SW').padEnd(8) + pb);
}
EOF

echo "== 实测解码路径 (每个视频播放 ~6.5s) =="
node "$TMPDIR/probe.mjs" "$PORT" "${FILES[@]}"
