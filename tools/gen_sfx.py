#!/usr/bin/env python3
"""Procedural placeholder audio generator for Town Defender.

Writes all SFX, the footstep, and the looping music to ../Audio/sfx/*.wav.
These are committed assets the game loads directly (see scripts/Sfx.gd) -- edit
this recipe and re-run to evolve the sounds, or just replace the .wav files with
hand-authored ones.

Run from the project root:  python3 tools/gen_sfx.py
"""
import wave, struct, math, random, os

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "Audio", "sfx")


def writew(name, samples):
    os.makedirs(OUT, exist_ok=True)
    out = bytearray()
    for s in samples:
        s = max(-1.0, min(1.0, s))
        out += struct.pack('<h', int(s * 30000))
    with wave.open(os.path.join(OUT, name + ".wav"), 'w') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR)
        f.writeframes(bytes(out))


def env(n, a=0.01, d=0.2):
    out = []; at = int(a * SR)
    for i in range(n):
        if i < at:
            out.append(i / max(1, at))
        else:
            t = (i - at) / max(1, (n - at))
            out.append(math.exp(-t * (1.0 / max(0.02, d)) * 3.0))
    return out


def tone(freq, n, kind='sine'):
    out = []
    for i in range(n):
        ph = 2 * math.pi * freq * i / SR
        if kind == 'square':
            out.append(1.0 if math.sin(ph) > 0 else -1.0)
        elif kind == 'saw':
            out.append(2.0 * ((freq * i / SR) % 1.0) - 1.0)
        else:
            out.append(math.sin(ph))
    return out


def noise(n):
    return [random.uniform(-1, 1) for _ in range(n)]


def mix(*sigs):
    n = max(len(s) for s in sigs)
    out = [0.0] * n
    for s in sigs:
        for i in range(len(s)):
            out[i] += s[i]
    return out


def apply(sig, e):
    return [sig[i] * e[i] for i in range(min(len(sig), len(e)))]


def sweep(f0, f1, n, kind='sine'):
    out = []; ph = 0.0
    for i in range(n):
        t = i / n; f = f0 + (f1 - f0) * t
        ph += 2 * math.pi * f / SR
        if kind == 'square':
            out.append(1.0 if math.sin(ph) > 0 else -1.0)
        elif kind == 'saw':
            out.append((ph / math.pi) % 2 - 1)
        else:
            out.append(math.sin(ph))
    return out


def note(freq, dur, kind='sine', a=0.005, d=0.25, vol=0.6):
    n = int(dur * SR)
    return [vol * x for x in apply(tone(freq, n, kind), env(n, a, d))]


def seq(notes):
    out = []
    for nn in notes:
        out += nn
    return out


def n2f(n):
    return 440.0 * (2.0 ** ((n - 69) / 12.0))


def gen_sfx():
    n = int(0.18 * SR); writew("swing", [0.5 * x for x in apply(noise(n), env(n, 0.04, 0.10))])
    n = int(0.14 * SR); writew("hit", mix([0.8 * x for x in apply(tone(160, n), env(n, 0.001, 0.10))],
                                          [0.5 * x for x in apply(noise(n), env(n, 0.001, 0.05))]))
    n = int(0.45 * SR); writew("enemy_death", [0.6 * x for x in mix(apply(sweep(320, 70, n, 'square'), env(n, 0.005, 0.4)),
                                                                    [0.4 * x for x in apply(noise(n), env(n, 0.005, 0.3))])])
    n = int(0.12 * SR); writew("chop", mix([0.7 * x for x in apply(tone(190, n), env(n, 0.001, 0.06))],
                                           [0.6 * x for x in apply(noise(n), env(n, 0.001, 0.025))]))
    writew("coin", seq([note(880, 0.06, 'square', 0.002, 0.5, 0.5), note(1320, 0.09, 'square', 0.002, 0.5, 0.5)]))
    writew("build", seq([note(392, 0.12, 'square', 0.005, 0.6, 0.45), note(523, 0.12, 'square', 0.005, 0.6, 0.45),
                         note(659, 0.18, 'square', 0.005, 0.7, 0.5)]))
    writew("hire", seq([note(523, 0.08, 'sine', 0.005, 0.5, 0.5), note(784, 0.12, 'sine', 0.005, 0.6, 0.5)]))
    n = int(0.6 * SR); horn = []
    for i in range(n):
        t = i / SR; f = 110 * (1.0 + 0.01 * math.sin(2 * math.pi * 6 * t))
        horn.append(((f * t) % 1.0) * 2 - 1)
    writew("wave", [0.55 * x for x in apply(horn, env(n, 0.06, 0.5))])
    n = int(0.18 * SR); writew("keep_hit", mix([0.9 * x for x in apply(tone(90, n), env(n, 0.001, 0.12))],
                                               [0.35 * x for x in apply(noise(n), env(n, 0.001, 0.05))]))
    n = int(0.22 * SR); writew("hero_hurt", [0.6 * x for x in mix(apply(sweep(240, 150, n, 'saw'), env(n, 0.005, 0.18)),
                                                                 [0.3 * x for x in apply(noise(n), env(n, 0.005, 0.1))])])
    writew("victory", seq([note(523, 0.13, 'square', 0.005, 0.6, 0.45), note(659, 0.13, 'square', 0.005, 0.6, 0.45),
                           note(784, 0.13, 'square', 0.005, 0.6, 0.45), note(1047, 0.3, 'square', 0.005, 0.8, 0.5)]))
    writew("defeat", seq([note(440, 0.18, 'saw', 0.005, 0.7, 0.45), note(349, 0.18, 'saw', 0.005, 0.7, 0.45),
                          note(262, 0.4, 'saw', 0.01, 0.9, 0.5)]))
    writew("click", note(1000, 0.03, 'square', 0.001, 0.2, 0.4))
    # footstep
    n = int(0.09 * SR); step = []
    for i in range(n):
        t = i / SR; e = math.exp(-t * 38.0)
        step.append(0.5 * (0.7 * math.sin(2 * math.pi * 110 * t) * e + 0.25 * random.uniform(-1, 1) * math.exp(-t * 70.0)))
    writew("step", step)


def gen_music():
    # gentle 16s seamless A-minor loop (pads + bass + sparse arpeggio); PCM so it
    # loops cleanly in Godot (see scripts/Sfx.gd which sets LOOP_FORWARD).
    chords = [(57, [57, 60, 64]), (53, [53, 57, 60]), (48, [48, 52, 55]), (55, [55, 59, 62])]  # Am F C G
    beat = 60.0 / 150.0
    chord_dur = 4.0
    L = int(chord_dur * len(chords) * SR)
    X = int(0.5 * SR)
    total = L + X
    buf = [0.0] * total

    def add_tone(start, dur, freq, amp, kind='sine', atk=0.2, rel=0.6):
        ns = int(dur * SR)
        for i in range(ns):
            idx = start + i
            if idx >= total:
                break
            t = i / SR
            e = min(1.0, t / atk) if t < atk else math.exp(-(t - atk) * rel * 2.0)
            ph = 2 * math.pi * freq * t
            v = 2.0 / math.pi * math.asin(math.sin(ph)) if kind == 'tri' else math.sin(ph)
            buf[idx] += amp * v * e

    for ci, (bass, triad) in enumerate(chords):
        cs = int(ci * chord_dur * SR)
        for nt in triad:
            add_tone(cs, chord_dur, n2f(nt), 0.10, 'sine', atk=0.6, rel=0.25)
        add_tone(cs, chord_dur, n2f(bass - 12), 0.16, 'sine', atk=0.05, rel=0.4)
        for b in range(4):
            add_tone(cs + int(b * beat * SR), 0.5, n2f(triad[b % len(triad)] + 12), 0.08, 'tri', atk=0.01, rel=2.2)
    out = [0.0] * L
    for i in range(L):
        if i < X:
            a = i / X
            out[i] = buf[i] * a + buf[L + i] * (1.0 - a)
        else:
            out[i] = buf[i]
    writew("music", [0.7 * v for v in out])


if __name__ == "__main__":
    gen_sfx()
    gen_music()
    print("wrote SFX + music to", os.path.normpath(OUT))
