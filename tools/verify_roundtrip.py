#!/usr/bin/env python3
# 三档往返验证（真实路径）：通过 D-Bus SetActiveProfile 切换，桥接服务负责写全链路
import subprocess, time

EFI = '/sys/firmware/efi/efivars/Setup-a04a27f4-df00-4d42-b552-39511302113d'
FW = {0: '极速', 1: '均衡', 2: '静谧'}
EXPECT = {
    'power-saver': ('low-power',            'powersave',   'power',               2),
    'balanced':    ('balanced-performance', 'powersave',   'balance_performance', 1),
    'performance': ('performance',          'performance', 'performance',         0),
}


def rd(p):
    try:
        return open(p).read().strip()
    except Exception as e:
        return f'ERR:{e}'


def fw():
    try:
        return open(EFI, 'rb').read()[4 + 0x230]
    except Exception:
        return None


def dbus_set(name):
    r = subprocess.run(['busctl', '--system', 'set-property',
                        'org.freedesktop.UPower.PowerProfiles',
                        '/org/freedesktop/UPower/PowerProfiles',
                        'org.freedesktop.UPower.PowerProfiles',
                        'ActiveProfile', 's', name],
                       capture_output=True, text=True)
    return r.returncode, (r.stderr or '').strip()


def dbus_get():
    r = subprocess.run(['busctl', '--system', 'get-property',
                        'org.freedesktop.UPower.PowerProfiles',
                        '/org/freedesktop/UPower/PowerProfiles',
                        'org.freedesktop.UPower.PowerProfiles', 'ActiveProfile'],
                       capture_output=True, text=True)
    out = r.stdout.strip()
    if r.returncode != 0:
        return f'ERR {r.stderr.strip()}'
    # busctl 输出形如: s "balanced"
    return out.split('"')[1] if '"' in out else out


print(f'{"D-Bus 目标":<12} {"总线回读":<14} {"内核档位":<22} {"governor":<12} {"epp":<20} {"固件":<8} 判定')
print('-' * 108)
ok = 0
fail_msg = []
for name, (pp_exp, g_exp, e_exp, fw_exp) in EXPECT.items():
    rc, err = dbus_set(name)
    time.sleep(1.5)
    act = dbus_get()
    pp = rd('/sys/firmware/acpi/platform_profile')
    g = rd('/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor')
    e = rd('/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference')
    f = fw()
    bad = []
    if rc != 0:
        bad.append(f'调用失败 {err}')
    if act != name:
        bad.append(f'总线={act}')
    if pp != pp_exp:
        bad.append(f'档位={pp}')
    if g != g_exp:
        bad.append(f'gov={g}')
    if e != e_exp:
        bad.append(f'epp={e}')
    if f != fw_exp:
        bad.append(f'固件={f}')
    good = not bad
    ok += good
    print(f'{name:<12} {act:<14} {pp:<22} {g:<12} {e:<20} '
          f'{FW.get(f, "?")}({f}){"":<3} {"✓" if good else "✗ " + " ".join(bad)}')
    if bad:
        fail_msg.append(name)

dbus_set('balanced')
time.sleep(1.5)
print('-' * 108)
print(f'结果：{ok}/3 档全链路通过；已回落到 balanced（现固件 {FW.get(fw())} / '
      f'governor {rd("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")}）')
