#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec * 1e-9;
}

/* STREAM 风格：copy / scale / add / triad，测可持续内存带宽 */
int main(int argc, char **argv) {
    long n = (argc > 1 ? atol(argv[1]) : 256) * 1024L * 1024L / 4;
    int reps = argc > 2 ? atoi(argv[2]) : 8;
    float *a = aligned_alloc(64, n * 4), *b = aligned_alloc(64, n * 4),
          *c = aligned_alloc(64, n * 4);
    if (!a || !b || !c) { fprintf(stderr, "alloc fail\n"); return 1; }
    #pragma omp parallel for
    for (long i = 0; i < n; i++) { a[i] = 1.0f; b[i] = 2.0f; c[i] = 0.5f; }

    double best[4] = {1e9, 1e9, 1e9, 1e9};
    for (int r = 0; r < reps; r++) {
        double t = now();
        #pragma omp parallel for
        for (long i = 0; i < n; i++) c[i] = a[i];
        t = now() - t; if (t < best[0]) best[0] = t;

        double sc = 1.5;
        t = now();
        #pragma omp parallel for
        for (long i = 0; i < n; i++) b[i] = sc * c[i];
        t = now() - t; if (t < best[1]) best[1] = t;

        t = now();
        #pragma omp parallel for
        for (long i = 0; i < n; i++) c[i] = a[i] + b[i];
        t = now() - t; if (t < best[2]) best[2] = t;

        t = now();
        #pragma omp parallel for
        for (long i = 0; i < n; i++) a[i] = b[i] + sc * c[i];
        t = now() - t; if (t < best[3]) best[3] = t;
    }
    double gb = (double)n * 4.0 / 1e9;
    printf("size=%.0fMB copy=%.2f scale=%.2f add=%.2f triad=%.2f GB/s\n",
           (double)n * 4 / 1e6,
           2 * gb / best[0], 2 * gb / best[1], 3 * gb / best[2], 4 * gb / best[3]);
    printf("chk=%.1f\n", a[0] + b[0] + c[0]);
    return 0;
}
