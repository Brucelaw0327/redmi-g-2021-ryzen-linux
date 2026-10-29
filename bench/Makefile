# 体检基准，现编现用（二进制不入库）
#
# 关于 OpenMP：stream.c 里有 #pragma omp parallel for，但 mem.sh 的设计是
# 「8 个进程 × 单线程」而不是「1 个进程 × 16 线程」—— 测内存带宽时多进程
# 才能压满双通道，OpenMP 的同步开销反而拖后腿。所以默认编译**不加**
# -fopenmp（pragma 被忽略，即单线程），这样才能复现 data/ 里的原始成绩。
# 需要单实例跑满核时用 `make stream-omp`，但别和 mem.sh 一起用（会超订）。

CC     ?= cc
OPT    ?= -O3 -march=native -ffast-math
CFLAGS ?= $(OPT) -Wall -Wno-unknown-pragmas
LDLIBS ?= -lm

BINS = flops stream stream_mt keywatch

.PHONY: all clean

all: $(BINS)

# flops.c 用了 AVX2 + FMA intrinsics，必须开对应指令集
flops: flops.c
	$(CC) $(CFLAGS) -mfma $< -o $@ $(LDLIBS)

# stream_mt 与 stream 同源：多进程跑多份，各自单线程
stream stream_mt: %: stream.c
	$(CC) $(CFLAGS) $< -o $@ $(LDLIBS)

# 可选：真·多线程版，单实例吃满所有核
stream-omp: stream.c
	$(CC) $(CFLAGS) -fopenmp $< -o $@ $(LDLIBS)

# 只依赖 linux/input.h，不需要数学库
keywatch: keywatch.c
	$(CC) $(CFLAGS) $< -o $@

clean:
	rm -f $(BINS) stream-omp iotest.bin
