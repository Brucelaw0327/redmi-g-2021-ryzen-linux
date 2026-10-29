#!/bin/bash
cd "$(dirname "$0")"
F=./iotest.bin
echo "=== 顺序写 8GB (O_DIRECT) ==="
dd if=/dev/zero of=$F bs=1M count=8192 oflag=direct 2>&1 | tail -1
sync
echo "=== 顺序读 8GB (O_DIRECT) ==="
dd if=$F of=/dev/null bs=1M iflag=direct 2>&1 | tail -1
echo "=== 4K 随机读 QD1 (20000 次, O_DIRECT) ==="
dd if=$F of=/dev/null bs=4k count=20000 iflag=direct 2>&1 | tail -1
echo "=== 4K 随机写 QD1 (20000 次, O_DIRECT) ==="
dd if=/dev/zero of=$F.rnd bs=4k count=20000 oflag=direct 2>&1 | tail -1
rm -f $F $F.rnd
echo "=== 温度恢复曲线（负载停止后 60s）==="
./monitor.sh 60 4
