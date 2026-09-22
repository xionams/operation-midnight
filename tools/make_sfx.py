import wave
import math
import struct
import random


RATE = 44100
PEAK = 10.0 ** (-3.0 / 20.0)
OUT = ".codex-output/audio/"


def env_exp(t, attack=0.001, decay=0.12):
    if t < attack:
        return t / attack
    return math.exp(-(t - attack) / decay)


def lp_filter(values, cutoff):
    a = math.exp(-2.0 * math.pi * cutoff / RATE)
    y = 0.0
    out = []
    for x in values:
        y = (1.0 - a) * x + a * y
        out.append(y)
    return out


def hp_filter(values, cutoff):
    a = math.exp(-2.0 * math.pi * cutoff / RATE)
    y = 0.0
    previous = 0.0
    out = []
    for x in values:
        y = a * (y + x - previous)
        previous = x
        out.append(y)
    return out


def noise(rng, n):
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def add(dst, src, start=0, gain=1.0):
    end = min(len(dst), start + len(src))
    for i in range(start, end):
        dst[i] += src[i - start] * gain


def burst(rng, seconds, decay, cutoff=None, high=False):
    n = int(seconds * RATE)
    raw = noise(rng, n)
    if cutoff is not None:
        raw = hp_filter(raw, cutoff) if high else lp_filter(raw, cutoff)
    return [x * env_exp(i / RATE, 0.0007, decay) for i, x in enumerate(raw)]


def body(seconds, freq, decay, triangle=False):
    n = int(seconds * RATE)
    out = []
    phase = 0.0
    for i in range(n):
        phase += freq / RATE
        s = (2.0 * abs(2.0 * (phase - math.floor(phase + 0.5))) - 1.0) if triangle else math.sin(2.0 * math.pi * phase)
        out.append(s * env_exp(i / RATE, 0.002, decay))
    return out


def sweep(seconds, start_hz, end_hz, decay, rng, noise_mix=0.0):
    n = int(seconds * RATE)
    out = []
    phase = 0.0
    raw = noise(rng, n)
    for i in range(n):
        p = i / max(1, n - 1)
        hz = start_hz * ((end_hz / start_hz) ** p)
        phase += hz / RATE
        tone = math.sin(2.0 * math.pi * phase)
        out.append((tone * (1.0 - noise_mix) + raw[i] * noise_mix) * env_exp(i / RATE, 0.002, decay))
    return out


def relay_click(rng, seconds, heavy=1.0):
    n = int(seconds * RATE)
    out = [0.0] * n
    tick = burst(rng, min(seconds, 0.025), 0.009, 2600, True)
    add(out, tick, 0, 0.85 * heavy)
    if n > int(0.006 * RATE):
        add(out, burst(rng, min(seconds - 0.006, 0.022), 0.012, 900, False), int(0.006 * RATE), 0.42 * heavy)
    return out


def make_rifle(rng):
    out = [0.0] * int(0.12 * RATE)
    add(out, burst(rng, 0.08, 0.018, 2500, True), 0, 1.0)
    add(out, body(0.06, 82, 0.025), 0, 0.12)
    return out


def make_cannon(rng, seconds=0.55, deep=1.0):
    out = [0.0] * int(seconds * RATE)
    add(out, body(min(seconds, 0.42), 52 * deep, 0.28), 0, 1.1)
    add(out, burst(rng, min(seconds, 0.22), 0.055, 1800, True), int(0.008 * RATE), 0.95)
    add(out, burst(rng, min(seconds, 0.36), 0.16, 180, False), 0, 0.33)
    return out


def make_explosion(rng, seconds, large=False):
    out = [0.0] * int(seconds * RATE)
    add(out, body(min(seconds, 0.75 if large else 0.45), 44 if large else 68, 0.58 if large else 0.28), 0, 1.0 if large else 0.8)
    add(out, burst(rng, min(seconds, 0.7), 0.25 if large else 0.14, 230, False), 0, 0.95)
    add(out, burst(rng, min(seconds, 0.12), 0.032, 2600, True), int(0.012 * RATE), 0.7)
    debris = burst(rng, min(seconds, 0.9), 0.36 if large else 0.16, 1100, True)
    add(out, debris, int(0.06 * RATE), 0.35)
    return out


def scaled(data, db):
    peak = max(1e-9, max(abs(x) for x in data))
    gain = PEAK / peak * (10.0 ** (db / 20.0))
    return [max(-1.0, min(1.0, x * gain)) for x in data]


def write_wav(name, data, gain_db):
    samples = scaled(data, gain_db)
    path = OUT + name
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(x * 32767.0)) for x in samples))
    print(name + " " + format(len(data) / RATE, ".3f") + " s")


def loop_crossfade(data):
    half = int(0.5 * RATE)
    for i in range(half):
        t = i / max(1, half - 1)
        first = data[i]
        last = data[len(data) - half + i]
        data[i] = first * (1.0 - t) + last * t
        data[len(data) - half + i] = first * t + last * (1.0 - t)
    return data


def ambient(rng):
    n = 10 * RATE
    raw = lp_filter(noise(rng, n), 900)
    out = []
    for i, x in enumerate(raw):
        drift = 0.72 + 0.28 * math.sin(2.0 * math.pi * i / RATE / 7.0)
        out.append(x * drift + 0.025 * math.sin(2.0 * math.pi * 0.19 * i / RATE))
    return loop_crossfade(out)


def drone(rng, combat=False):
    n = 12 * RATE
    out = [0.0] * n
    partials = ((55.0, 0.42), (82.4, 0.28), (110.2, 0.19))
    high = lp_filter(noise(rng, n), 1250 if combat else 700)
    for i in range(n):
        t = i / RATE
        slow = 1.0 + 0.045 * math.sin(2.0 * math.pi * 0.071 * t)
        value = sum(a * math.sin(2.0 * math.pi * (f * (1.0 + 0.002 * math.sin(2.0 * math.pi * 0.11 * t))) * t) for f, a in partials)
        if combat:
            value *= 0.84 + 0.16 * (0.5 + 0.5 * math.sin(2.0 * math.pi * 1.6 * t))
            value += high[i] * 0.10
        out[i] = value * slow
    return loop_crossfade(out)


def build():
    cues = [
        ("rifle_shot.wav", 1, make_rifle, -14),
        ("at_launcher.wav", 2, lambda r: add_layers(r, 0.45, "at"), -12),
        ("cannon_shot.wav", 3, make_cannon, -8),
        ("artillery_shot.wav", 4, lambda r: make_cannon(r, 0.9, 0.82), -7),
        ("mg_burst.wav", 5, lambda r: multi_rifle(r, 0.35), -15),
        ("impact_small.wav", 6, lambda r: impact(r, 0.12, False), -18),
        ("impact_shell.wav", 7, lambda r: impact(r, 0.4, True), -12),
        ("explosion_small.wav", 8, lambda r: make_explosion(r, 0.8, False), -9),
        ("explosion_large.wav", 9, lambda r: make_explosion(r, 1.4, True), -6),
        ("select.wav", 10, lambda r: relay_click(r, 0.05), -20),
        ("order.wav", 11, lambda r: two_clack(r), -18),
        ("build_place.wav", 12, lambda r: build_place(r), -14),
        ("build_done.wav", 13, lambda r: build_done(r), -13),
        ("unit_ready.wav", 14, lambda r: servo(r), -15),
        ("capture.wav", 15, lambda r: capture(r), -13),
        ("sell.wav", 16, lambda r: sell(r), -14),
        ("low_power.wav", 17, lambda r: low_power(r), -12),
        ("victory.wav", 18, lambda r: match_sting(r, True), -8),
        ("defeat.wav", 19, lambda r: match_sting(r, False), -8),
    ]
    for name, seed, maker, gain in cues:
        write_wav(name, maker(random.Random(seed)), gain)
    write_wav("ambient_wind.wav", ambient(random.Random(20)), -26)
    write_wav("music_calm.wav", drone(random.Random(21), False), -22)
    write_wav("music_combat.wav", drone(random.Random(22), True), -20)


def add_layers(rng, seconds, kind):
    out = [0.0] * int(seconds * RATE)
    add(out, sweep(0.34, 95, 260, 0.22, rng, 0.28), int(0.03 * RATE), 0.72)
    add(out, burst(rng, 0.16, 0.075, 1200, False), 0, 0.5)
    add(out, body(0.09, 68, 0.08), 0, 0.35)
    return out


def multi_rifle(rng, seconds):
    out = [0.0] * int(seconds * RATE)
    for i, at in enumerate((0.0, 0.105, 0.21)):
        add(out, make_rifle(random.Random(500 + i)), int(at * RATE), 0.82)
    return out


def impact(rng, seconds, shell):
    out = [0.0] * int(seconds * RATE)
    add(out, burst(rng, min(seconds, 0.11 if not shell else 0.27), 0.08 if not shell else 0.17, 3200, True), 0, 0.72)
    add(out, burst(rng, seconds, 0.09 if not shell else 0.22, 480, False), int(0.008 * RATE), 0.8)
    if shell:
        add(out, body(0.22, 76, 0.16), 0, 0.42)
        add(out, burst(rng, 0.16, 0.05, 2200, True), int(0.11 * RATE), 0.28)
    return out


def two_clack(rng):
    out = [0.0] * int(0.09 * RATE)
    add(out, relay_click(rng, 0.038, 0.8), 0, 1.0)
    add(out, relay_click(rng, 0.035, 0.72), int(0.042 * RATE), 0.82)
    return out


def build_place(rng):
    out = [0.0] * int(0.25 * RATE)
    add(out, body(0.14, 58, 0.12, True), 0, 0.72)
    add(out, burst(rng, 0.12, 0.055, 950, False), int(0.015 * RATE), 0.75)
    add(out, burst(rng, 0.07, 0.025, 3000, True), 0, 0.38)
    return out


def build_done(rng):
    out = [0.0] * int(0.4 * RATE)
    add(out, sweep(0.21, 520, 130, 0.16, rng, 0.18), 0, 0.45)
    add(out, body(0.19, 62, 0.16), int(0.18 * RATE), 0.48)
    add(out, burst(rng, 0.10, 0.05, 1700, True), int(0.18 * RATE), 0.28)
    return out


def servo(rng):
    out = [0.0] * int(0.3 * RATE)
    add(out, sweep(0.24, 180, 440, 0.22, rng, 0.32), 0, 0.46)
    add(out, burst(rng, 0.24, 0.19, 850, False), 0, 0.18)
    return out


def capture(rng):
    out = [0.0] * int(0.5 * RATE)
    for i in range(5):
        add(out, relay_click(rng, 0.045, 0.76), int((0.045 + i * 0.085) * RATE), 0.82 - i * 0.05)
    return out


def sell(rng):
    out = [0.0] * int(0.5 * RATE)
    for i in range(7):
        add(out, relay_click(rng, 0.04, 0.72), int((0.02 + i * 0.065) * RATE), 0.92 - i * 0.08)
    return out


def low_power(rng):
    out = [0.0] * int(0.9 * RATE)
    add(out, sweep(0.82, 92, 44, 0.75, rng, 0.22), 0, 0.65)
    add(out, lp_filter(noise(rng, len(out)), 260), 0, 0.13)
    return out


def match_sting(rng, victory):
    seconds = 2.2 if victory else 2.4
    out = [0.0] * int(seconds * RATE)
    n = len(out)
    raw = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    phase = 0.0
    for i in range(n):
        t = i / RATE
        p = i / max(1, n - 1)
        if victory:
            hz = 70.0 + 18.0 * p
            amp = min(1.0, t / 0.5) * math.exp(-0.12 * max(0.0, t - 1.4))
        else:
            hz = 86.0 - 28.0 * p
            amp = min(1.0, t / 0.25) * math.exp(-0.55 * max(0.0, t - 1.0))
        phase += hz / RATE
        saw = 2.0 * (phase - math.floor(phase + 0.5))
        out[i] = (0.72 * saw + 0.20 * math.sin(2.0 * math.pi * phase * 1.51) + 0.08 * raw[i]) * amp
    return out


if __name__ == "__main__":
    build()
