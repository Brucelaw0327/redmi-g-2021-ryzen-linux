#define _GNU_SOURCE
#include <immintrin.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec * 1e-9;
}

/* 8 条独立 FMA 依赖链，饱和 Zen3 每核 2 条 256bit FMA 管线 */
int main(int argc, char **argv) {
    int burn = (argc > 1 && argv[1][0] == 'b'); /* burn = 无限负载，用于热测试 */
    long iters = burn ? 4000000000L : (argc > 1 ? atol(argv[1]) : 20000000L);
    __m256 b = _mm256_set1_ps(1.0000001f);
    __m256 c = _mm256_set1_ps(1e-7f);
    __m256 a0 = _mm256_set1_ps(1.0f), a1 = a0, a2 = a0, a3 = a0,
           a4 = a0, a5 = a0, a6 = a0, a7 = a0;

    double t0 = now();
    for (long r = 0; burn || r == 0; r++) {
      for (long i = 0; i < iters; i++) {
        a0 = _mm256_fmadd_ps(a0, b, c);
        a1 = _mm256_fmadd_ps(a1, b, c);
        a2 = _mm256_fmadd_ps(a2, b, c);
        a3 = _mm256_fmadd_ps(a3, b, c);
        a4 = _mm256_fmadd_ps(a4, b, c);
        a5 = _mm256_fmadd_ps(a5, b, c);
        a6 = _mm256_fmadd_ps(a6, b, c);
        a7 = _mm256_fmadd_ps(a7, b, c);
      }
    }
    double t1 = now();

    a0 = _mm256_add_ps(a0, a1); a2 = _mm256_add_ps(a2, a3);
    a4 = _mm256_add_ps(a4, a5); a6 = _mm256_add_ps(a6, a7);
    a0 = _mm256_add_ps(a0, a2); a0 = _mm256_add_ps(a0, a4);
    a0 = _mm256_add_ps(a0, a6);
    float tmp[8];
    _mm256_storeu_ps(tmp, a0);
    float s = 0;
    for (int i = 0; i < 8; i++) s += tmp[i];

    double flops = (double)iters * 8.0 * 8.0 * 2.0;
    printf("%.2f|%.4f|%.0f\n", flops / (t1 - t0) / 1e9, t1 - t0, s);
    return 0;
}
