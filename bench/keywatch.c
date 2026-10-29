/* keywatch —— 只打印按键事件，用来确认 Fn+K 之类的组合键有没有进内核
 * 编译: gcc -O2 -o keywatch keywatch.c
 * 运行: sudo ./keywatch
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <poll.h>
#include <errno.h>
#include <linux/input.h>
#include <sys/ioctl.h>

#define MAXD 64

static const char *keyname(unsigned c) {
    static char b[32];
    switch (c) {
    case KEY_A: return "A"; case KEY_B: return "B"; case KEY_C: return "C";
    case KEY_D: return "D"; case KEY_E: return "E"; case KEY_F: return "F";
    case KEY_G: return "G"; case KEY_H: return "H"; case KEY_I: return "I";
    case KEY_J: return "J"; case KEY_K: return "K"; case KEY_L: return "L";
    case KEY_M: return "M"; case KEY_N: return "N"; case KEY_O: return "O";
    case KEY_P: return "P"; case KEY_Q: return "Q"; case KEY_R: return "R";
    case KEY_S: return "S"; case KEY_T: return "T"; case KEY_U: return "U";
    case KEY_V: return "V"; case KEY_W: return "W"; case KEY_X: return "X";
    case KEY_Y: return "Y"; case KEY_Z: return "Z";
    case KEY_F1: return "F1"; case KEY_F2: return "F2"; case KEY_F3: return "F3";
    case KEY_F4: return "F4"; case KEY_F5: return "F5"; case KEY_F6: return "F6";
    case KEY_F7: return "F7"; case KEY_F8: return "F8"; case KEY_F9: return "F9";
    case KEY_F10: return "F10"; case KEY_F11: return "F11"; case KEY_F12: return "F12";
    case KEY_LEFTMETA: return "Meta(Super)";
    case KEY_LEFTSHIFT: return "Shift";
    case KEY_LEFTCTRL: return "Ctrl";
    case KEY_LEFTALT: return "Alt";
    case KEY_BRIGHTNESSDOWN: return "亮度-";
    case KEY_BRIGHTNESSUP: return "亮度+";
    case KEY_VOLUMEDOWN: return "音量-";
    case KEY_VOLUMEUP: return "音量+";
    case KEY_MUTE: return "静音";
    case KEY_WLAN: return "无线开关";
    case KEY_PROG1: return "PROG1(厂商键)";
    case KEY_PROG2: return "PROG2(厂商键)";
    case KEY_PROG3: return "PROG3(厂商键)";
    case KEY_PROG4: return "PROG4(厂商键)";
    default:
        snprintf(b, sizeof b, "code %u (0x%x)", c, c);
        return b;
    }
}

struct dev { int fd; char name[256]; };

int main(void) {
    struct dev d[MAXD];
    int n = 0;
    DIR *dir = opendir("/dev/input");
    if (!dir) {
        fprintf(stderr, "打不开 /dev/input：%s\n请用 sudo 运行。\n", strerror(errno));
        return 1;
    }
    struct dirent *e;
    while ((e = readdir(dir)) && n < MAXD) {
        if (strncmp(e->d_name, "event", 5)) continue;
        char p[300];
        snprintf(p, sizeof p, "/dev/input/%s", e->d_name);
        int fd = open(p, O_RDONLY | O_NONBLOCK);
        if (fd < 0) continue;
        unsigned long bits = 0;
        if (ioctl(fd, EVIOCGBIT(0, sizeof bits), &bits) < 0 || !(bits & (1UL << EV_KEY))) {
            close(fd); continue;
        }
        d[n].fd = fd;
        if (ioctl(fd, EVIOCGNAME(sizeof d[n].name), d[n].name) < 0)
            strcpy(d[n].name, e->d_name);
        printf("监听 %-12s %s\n", e->d_name, d[n].name);
        n++;
    }
    closedir(dir);

    if (!n) { fprintf(stderr, "没有可读的输入设备\n"); return 1; }

    printf("\n共 %d 个设备。现在按 Fn+K（用笔记本自带键盘），Ctrl+C 结束。\n", n);
    printf("-----------------------------------------------------------\n");
    fflush(stdout);

    struct pollfd pfd[MAXD];
    for (int i = 0; i < n; i++) { pfd[i].fd = d[i].fd; pfd[i].events = POLLIN; }

    for (;;) {
        int r = poll(pfd, n, 500);
        if (r < 0) { if (errno == EINTR) continue; perror("poll"); break; }
        if (r == 0) continue;
        for (int i = 0; i < n; i++) {
            if (!(pfd[i].revents & POLLIN)) continue;
            struct input_event ev[64];
            ssize_t len = read(d[i].fd, ev, sizeof ev);
            if (len <= 0) continue;
            int cnt = (int)(len / sizeof(struct input_event));
            for (int j = 0; j < cnt; j++) {
                if (ev[j].type != EV_KEY || ev[j].value == 2) continue; /* 忽略长按重复 */
                printf("[%s] %-22s %-4s\n", d[i].name, keyname(ev[j].code),
                       ev[j].value ? "按下" : "松开");
                fflush(stdout);
            }
        }
    }
    return 0;
}
