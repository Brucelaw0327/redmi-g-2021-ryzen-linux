#!/bin/bash
cd "$(dirname "$0")"
DUR=${1:-400}
echo "启动 16 线程满载，持续 ${DUR}s ..."
for i in $(seq 1 16); do ./flops burn & done
BURNPIDS=$(jobs -p)
./monitor.sh "$DUR" 3 > soak.csv &
MONPID=$!
wait $MONPID
kill $BURNPIDS 2>/dev/null
sleep 1
pkill -f "flops burn" 2>/dev/null
echo "负载已停止"
