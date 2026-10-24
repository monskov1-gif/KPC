"""Временный звук игры — синтезируется этим скриптом (без чужих сэмплов): музыка, окружение, шаги, интерфейс.
Всё помечено как временное (docs/AUDIO.md): заменить на записанную музыку и звуки, когда они появятся.

Запуск: python3 tools/audio/gen_audio.py [имя ...]   → audio/{music,ambient,sfx}/*.ogg (ffmpeg, libvorbis)
Музыка — бесшовные петли: хвост реверберации переносится в начало, длина — целое число тактов.
"""
import math
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 32000
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "audio")

# ------------------------------------------------------------------ основа


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


NOTE = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8,
        "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}
QUAL = {"": (0, 4, 7), "m": (0, 3, 7), "maj7": (0, 4, 7, 11), "m7": (0, 3, 7, 10), "7": (0, 4, 7, 10),
        "m9": (0, 3, 7, 10, 14), "6": (0, 4, 7, 9), "sus4": (0, 5, 7), "add9": (0, 4, 7, 14), "sus2": (0, 2, 7)}


def chord(name, octave=4):
    """'Am7' → корень (midi) и ступени."""
    root = name[0] + (name[1] if len(name) > 1 and name[1] in "#b" else "")
    q = name[len(root):]
    r = 12 * (octave + 1) + NOTE[root]
    return r, [r + i for i in QUAL[q]]


def t_axis(n):
    return np.arange(n) / SR


def env(n, a=0.005, d=0.3, s=0.0, r=0.05, hold=None):
    """Огибающая: атака, экспоненциальный спад к уровню s, отпускание в конце."""
    t = t_axis(n)
    e = np.minimum(1.0, t / max(a, 1e-4))
    e = e * (s + (1 - s) * np.exp(-np.maximum(0, t - a) / max(d, 1e-4)))
    rn = int(r * SR)
    if 0 < rn < n:
        e[-rn:] *= np.linspace(1, 0, rn) ** 2
    return e


def fft_filter(x, lo=None, hi=None, slope=2.0):
    """Мягкий полосовой фильтр в частотной области (без scipy)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = np.ones_like(f)
    if hi:
        g *= 1 / (1 + (f / hi) ** (2 * slope))
    if lo:
        g *= 1 / (1 + (lo / np.maximum(f, 1e-3)) ** (2 * slope))
    return np.fft.irfft(X * g, len(x))


def noise(n, rng, color="white"):
    w = rng.standard_normal(n)
    if color == "white":
        return w
    X = np.fft.rfft(w)
    f = np.maximum(np.fft.rfftfreq(n, 1 / SR), 20)
    X = X / (np.sqrt(f) if color == "pink" else f)
    y = np.fft.irfft(X, n)
    return y / (np.abs(y).max() + 1e-9)


# ------------------------------------------------------------------ инструменты


def epiano(f, dur, vel=0.6):
    """Электропиано (ЧМ-синтез, как у Rhodes): мягкий удар, тёплый спад."""
    n = int((dur + 1.2) * SR)
    t = t_axis(n)
    idx = 1.6 * np.exp(-t * 3.5) + 0.25
    mod = np.sin(2 * np.pi * f * t) * idx
    car = np.sin(2 * np.pi * f * t + mod) + 0.25 * np.sin(2 * np.pi * f * 2.0 * t + mod * 0.5) * np.exp(-t * 2)
    tine = 0.12 * np.sin(2 * np.pi * f * 7.0 * t) * np.exp(-t * 14)
    e = env(n, a=0.003, d=1.1 + 200 / f, s=0.0, r=0.0)
    off = int(dur * SR)
    e[off:] *= np.exp(-t_axis(n - off) * 7)
    return (car + tine) * e * vel


def musicbox(f, dur, vel=0.6):
    """Музыкальная шкатулка / колокольчик: негармонические обертоны, быстрый спад."""
    n = int((dur + 1.6) * SR)
    t = t_axis(n)
    y = (np.sin(2 * np.pi * f * t) * np.exp(-t * 2.2) + 0.35 * np.sin(2 * np.pi * f * 3.01 * t) * np.exp(-t * 6)
         + 0.18 * np.sin(2 * np.pi * f * 5.43 * t) * np.exp(-t * 11) + 0.08 * np.sin(2 * np.pi * f * 8.9 * t) * np.exp(-t * 20))
    return y * np.minimum(1, t / 0.002) * vel


def glock(f, dur, vel=0.5):
    n = int((dur + 1.2) * SR)
    t = t_axis(n)
    y = np.sin(2 * np.pi * f * t) * np.exp(-t * 3) + 0.4 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 8) \
        + 0.15 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t * 16)
    return y * np.minimum(1, t / 0.001) * vel


def pluck(f, dur, vel=0.6, bright=0.5, rng=None):
    """Щипок (укулеле, пиццикато): Карплус — Стронг, посчитанный периодами (векторно)."""
    rng = rng or np.random.default_rng(int(f * 10))
    n = int((dur + 0.6) * SR)
    p = max(2, int(SR / f))
    buf = rng.uniform(-1, 1, p)
    buf = fft_filter(np.tile(buf, 4), hi=1500 + 6000 * bright)[:p]
    out = np.empty(n + p)
    out[:p] = buf
    damp = 0.996 - 0.004 * (1 - bright)
    i = p
    while i < n + p:
        k = min(p, n + p - i)
        prev = out[i - p:i - p + k]
        prev2 = out[i - p - 1:i - p - 1 + k] if i - p - 1 >= 0 else np.concatenate([[0], prev[:-1]])
        if len(prev2) < k:
            prev2 = np.concatenate([[0], prev[:k - 1]])
        out[i:i + k] = damp * 0.5 * (prev + prev2)
        i += k
    y = out[p:]
    off = int(dur * SR)
    y[off:] *= np.exp(-t_axis(n - off) * 12)
    return y * vel


def pad(freqs, dur, vel=0.3, bright=0.5, attack=0.8):
    """Подушка: сумма гармоник с хорусом, медленная атака и спад."""
    n = int((dur + 1.5) * SR)
    t = t_axis(n)
    y = np.zeros(n)
    for f in freqs:
        for det in (-0.004, 0.0, 0.005):
            ff = f * (1 + det)
            for h in range(1, 7):
                a = (1.0 / h) * (bright ** (h - 1))
                y += a * np.sin(2 * np.pi * ff * h * t + h * 1.7 + det * 400)
    e = np.minimum(1, t / attack)
    off = int(dur * SR)
    e[off:] *= np.exp(-t_axis(n - off) * 3)
    return y * e * vel / (len(freqs) * 3)


def bass(f, dur, vel=0.5):
    n = int((dur + 0.3) * SR)
    t = t_axis(n)
    y = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * f * 2 * t) + 0.08 * np.sin(2 * np.pi * f * 3 * t)
    e = env(n, a=0.01, d=0.9, s=0.35, r=0.12)
    off = int(dur * SR)
    e[off:] *= np.exp(-t_axis(n - off) * 20)
    return y * e * vel


def kick(vel=0.6):
    n = int(0.35 * SR)
    t = t_axis(n)
    f = 45 + 90 * np.exp(-t * 30)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t * 9) * vel


def brush(rng, vel=0.25, dur=0.18, lo=2500, hi=9000):
    n = int(dur * SR)
    y = fft_filter(rng.standard_normal(n), lo=lo, hi=hi)
    return y / (np.abs(y).max() + 1e-9) * env(n, a=0.004, d=dur / 3, r=0.02) * vel


def shaker(rng, vel=0.15):
    return brush(rng, vel, 0.09, 5000, 12000)


def low_shelf(x, cut=0.45, f0=110.0, f1=320.0):
    """Срез низа (−7 дБ ниже f0, плавно к f1): на динамиках телефона бас не гудит и не глушит мелодию."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    k = np.clip((np.log(np.maximum(f, 1)) - math.log(f0)) / (math.log(f1) - math.log(f0)), 0, 1)
    g = cut + (1 - cut) * (k * k * (3 - 2 * k))
    g[f < 35] *= (f[f < 35] / 35) ** 2
    return np.fft.irfft(X * g, len(x))


def reverb(x, seconds=2.2, mix=0.25, rng=None, loop=False):
    """Свёртка с синтетическим откликом зала. loop=True — хвост заворачивается в начало (бесшовная петля)."""
    rng = rng or np.random.default_rng(7)
    n = int(seconds * SR)
    t = t_axis(n)
    ir = rng.standard_normal(n) * np.exp(-t * 6.9 / seconds)
    ir = fft_filter(ir, hi=6000) * np.exp(-t * 1.5)
    ir[:int(0.012 * SR)] = 0
    ir /= np.sqrt((ir ** 2).sum()) + 1e-9
    L = len(x) + n
    N = 1 << (L - 1).bit_length()
    wet = np.fft.irfft(np.fft.rfft(x, N) * np.fft.rfft(ir, N), N)[:L]
    if loop:
        tail = wet[len(x):]
        wet = wet[:len(x)].copy()
        wet[:len(tail)] += tail
    else:
        x = np.concatenate([x, np.zeros(n)])
    return x * (1 - mix * 0.5) + wet * mix * 3.0


# ------------------------------------------------------------------ композиция


class Track:
    def __init__(self, bpm, beats_per_bar, bars, seed):
        self.bpm = bpm
        self.bpb = beats_per_bar
        self.bars = bars
        self.beat = 60.0 / bpm
        self.n = int(round(bars * beats_per_bar * self.beat * SR))
        self.L = np.zeros(self.n)
        self.R = np.zeros(self.n)
        self.rng = np.random.default_rng(seed)

    def add(self, y, beat_pos, pan=0.0, gain=1.0):
        """Ноту за концом петли заворачиваем в начало — петля бесшовная."""
        i = int(round(beat_pos * self.beat * SR)) % self.n
        y = y * gain
        gl, gr = math.cos((pan + 1) * math.pi / 4), math.sin((pan + 1) * math.pi / 4)
        k = 0
        while k < len(y):
            j = (i + k) % self.n
            m = min(len(y) - k, self.n - j)
            self.L[j:j + m] += y[k:k + m] * gl
            self.R[j:j + m] += y[k:k + m] * gr
            k += m

    def finish(self, rev=0.28, rev_s=2.4, vinyl=0.0):
        L = reverb(self.L, rev_s, rev, np.random.default_rng(1), loop=True)
        R = reverb(self.R, rev_s, rev, np.random.default_rng(2), loop=True)
        if vinyl:
            nz = fft_filter(self.rng.standard_normal(self.n), lo=800, hi=5000) * vinyl * 0.02
            L, R = L + nz, R + np.roll(nz, 1000)
        L, R = low_shelf(L), low_shelf(R)
        st = np.stack([L, R], 1)
        return st / (np.abs(st).max() + 1e-9) * 0.8


def melody_line(tr, prog, chord_beats, octave, rng, density=0.5, motif_len=None, style="step"):
    """Мелодия: мотив из тонов аккорда и проходящих нот; повторяется с вариациями (A A' B A).
    Возвращает [(доля, midi, длительность в долях)]."""
    scale_root = chord(prog[0], octave)[0]
    major = [0, 2, 4, 5, 7, 9, 11]
    minor = [0, 2, 3, 5, 7, 8, 10]
    q0 = prog[0][2:] if len(prog[0]) > 1 and prog[0][1] in "#b" else prog[0][1:]
    sc = minor if q0.startswith("m") and not q0.startswith("maj") else major
    notes_in_scale = [scale_root + o * 12 + s for o in (-1, 0, 1) for s in sc]
    bars = len(prog)
    motif_len = motif_len or chord_beats
    rhythms = [[1, 1, 2], [2, 1, 1], [1.5, 0.5, 2], [1, 0.5, 0.5, 2], [3, 1], [2, 2], [1, 1, 1, 1]] if chord_beats == 4 \
        else [[1, 1, 1], [2, 1], [1, 2], [1.5, 0.5, 1], [3]]
    phrase = []
    motif_a = [rhythms[rng.integers(len(rhythms))] for _ in range(2)]
    motif_b = [rhythms[rng.integers(len(rhythms))] for _ in range(2)]
    last = scale_root + 12 * (0 if octave >= 5 else 1) + 4
    for b in range(bars):
        r, tones = chord(prog[b], octave)
        section = (b // 2) % 4
        rhythm = (motif_b if section == 2 else motif_a)[b % 2]
        if rng.random() > density + 0.3 and section != 0:
            rhythm = [chord_beats]
        pos = b * chord_beats
        for k, d in enumerate(rhythm):
            strong = k == 0 or d >= 2
            cands = [x for x in notes_in_scale if (x - r) % 12 in [(t - r) % 12 for t in tones]] if strong else notes_in_scale
            cands = [x for x in cands if abs(x - last) <= (5 if style == "step" else 9)] or cands
            weights = np.array([1.0 / (1 + abs(x - last)) for x in cands])
            nxt = cands[rng.choice(len(cands), p=weights / weights.sum())]
            if b == bars - 1 and k == len(rhythm) - 1:
                nxt = min((x for x in notes_in_scale if (x - r) % 12 == 0), key=lambda x: abs(x - last))
            phrase.append((pos, nxt, d))
            last = nxt
            pos += d
    return phrase


def arrange(name, bpm, bpb, prog, seed, lead, comp, bass_on=True, drums=None, lead_oct=5, pad_on=True,
            rev=0.3, vinyl=0.0, density=0.55, lead_gain=1.0, comp_gain=1.0, repeats=2):
    prog = prog * repeats
    tr = Track(bpm, bpb, len(prog), seed)
    rng = tr.rng
    # аккомпанемент
    for b, c in enumerate(prog):
        r, tones = chord(c, 3 if comp != "pluck_strum" else 4)
        voiced = [x if x >= r + 3 or x == r else x + 12 for x in tones]
        pos = b * bpb
        if comp == "epiano":
            for k, x in enumerate(voiced[1:] + [voiced[0] + 12]):
                tr.add(epiano(midi(x + 12), bpb * tr.beat * 0.95, 0.22), pos + 0.02 * k, pan=-0.3 + 0.2 * k, gain=comp_gain)
            if bpb == 4:
                for k, x in enumerate(voiced[1:3]):
                    tr.add(epiano(midi(x + 12), 0.4, 0.12), pos + 2.5, pan=0.3, gain=comp_gain)
        elif comp == "pluck_strum":
            pattern = [0, 1, 1.5, 2.5, 3] if bpb == 4 else [0, 1, 2]
            for p in pattern:
                for k, x in enumerate(voiced):
                    tr.add(pluck(midi(x), 0.4, 0.18, 0.55, rng), pos + p + 0.012 * k, pan=-0.25, gain=comp_gain)
        elif comp == "arp":
            seq = (voiced + [voiced[1] + 12]) * 2
            step = 0.5
            for k in range(int(bpb / step)):
                tr.add(musicbox(midi(seq[k % len(seq)] + 12), 0.4, 0.16), pos + k * step, pan=0.35 * math.sin(k), gain=comp_gain)
        elif comp == "pizz":
            for p in range(bpb):
                x = voiced[(p + b) % len(voiced)]
                tr.add(pluck(midi(x + 12), 0.25, 0.25, 0.35, rng), pos + p, pan=-0.3 + 0.2 * (p % 3), gain=comp_gain)
        elif comp == "piano_sparse":
            tr.add(epiano(midi(r), bpb * tr.beat, 0.28), pos, pan=-0.2, gain=comp_gain)
            for k, x in enumerate(voiced[1:]):
                tr.add(epiano(midi(x + 12), bpb * tr.beat * 0.8, 0.14), pos + 1 + k * 0.5, pan=0.2, gain=comp_gain)
        elif comp == "drone":
            tr.add(pad([midi(r - 12), midi(r - 5)], bpb * tr.beat, 0.4, 0.4, 0.3), pos, gain=comp_gain)
            tr.add(pad([midi(x + 12) for x in tones], bpb * tr.beat, 0.35, 0.6, 1.2), pos, gain=comp_gain)
            for p in range(0, bpb * 2):
                tr.add(pluck(midi(r - 12 + (1 if p % 4 == 3 else 0)), 0.22, 0.25, 0.25, rng), pos + p * 0.5, gain=comp_gain)
        if pad_on:
            tr.add(pad([midi(x + 12) for x in voiced], bpb * tr.beat, 0.25, 0.45), pos, gain=0.9)
        if bass_on:
            tr.add(bass(midi(r - 12), bpb * tr.beat * 0.55, 0.55), pos, gain=0.6)
            if bpb == 4:
                tr.add(bass(midi(r - 12 + (7 if b % 2 else 12)), tr.beat * 0.9, 0.35), pos + 2.5, gain=0.6)
    # мелодия
    if lead:
        line = melody_line(tr, prog, bpb, lead_oct, rng, density)
        inst = {"musicbox": musicbox, "glock": glock, "epiano": epiano, "pluck": None}[lead]
        for pos, nt, d in line:
            if lead == "pluck":
                y = pluck(midi(nt), d * tr.beat, 0.35, 0.7, rng)
            else:
                y = inst(midi(nt), d * tr.beat, 0.4)
            tr.add(y, pos, pan=0.15, gain=lead_gain)
    # ударные
    if drums:
        for b in range(len(prog)):
            pos = b * bpb
            if drums in ("soft", "lofi"):
                tr.add(kick(0.38), pos)
                if bpb == 4:
                    tr.add(kick(0.25), pos + 2.5 if drums == "lofi" else pos + 2)
                    tr.add(brush(rng, 0.22, 0.25, 1500, 7000), pos + 1)
                    tr.add(brush(rng, 0.22, 0.25, 1500, 7000), pos + 3)
                for h in range(bpb * 2):
                    tr.add(shaker(rng, 0.09 if h % 2 else 0.13), pos + h * 0.5 + (0.03 if h % 2 and drums == "lofi" else 0), pan=0.4)
            elif drums == "shaker":
                for h in range(bpb * 2):
                    tr.add(shaker(rng, 0.07 if h % 2 else 0.11), pos + h * 0.5, pan=0.3)
            elif drums == "timpani":
                tr.add(kick(0.7), pos)
                tr.add(kick(0.4), pos + bpb - 0.5)
    return tr.finish(rev=rev, vinyl=vinyl)


MUSIC = {
    # главное меню: «облачный вальс» — шкатулка и подушка
    "title": lambda: arrange("title", 84, 3, ["F", "Dm", "Bb", "C", "F", "Am", "Bb", "Csus4"], 11, "musicbox", "arp",
                             drums=None, lead_oct=5, rev=0.38, density=0.5),
    # улица днём: укулеле, колокольчики, шейкер
    "city_day": lambda: arrange("city_day", 104, 4, ["C", "Am", "F", "G", "C", "Em", "F", "G"], 21, "glock", "pluck_strum",
                                drums="soft", lead_oct=5, rev=0.22, density=0.6, lead_gain=0.8),
    # дом: тёплое электропиано
    "home": lambda: arrange("home", 76, 4, ["Gmaj7", "Em7", "Cmaj7", "D", "Gmaj7", "Em7", "Am7", "D"], 31,
                            "epiano", "epiano", drums="shaker", lead_oct=5, rev=0.3, density=0.45, lead_gain=0.9),
    # склон: зимние колокольчики в 3/4
    "winter": lambda: arrange("winter", 92, 3, ["D", "Bm", "G", "A", "D", "F#m", "G", "A"], 41, "glock", "arp",
                              drums="shaker", lead_oct=5, rev=0.4, density=0.55),
    # крыша вечером: лоу-фай
    "evening": lambda: arrange("evening", 70, 4, ["Am7", "Fmaj7", "Cmaj7", "G6"], 51, "epiano", "epiano",
                               drums="lofi", lead_oct=5, rev=0.3, vinyl=1.0, density=0.4, repeats=4),
    # ночь: колыбельная
    "night": lambda: arrange("night", 60, 3, ["Eb", "Cm", "Ab", "Bb", "Eb", "Gm", "Ab", "Bb"], 61, "musicbox", "arp",
                             bass_on=False, drums=None, lead_oct=5, rev=0.45, density=0.35, comp_gain=0.7),
    # больница, опека: грустное фортепиано
    "sad": lambda: arrange("sad", 62, 4, ["Dm", "Bb", "F", "A", "Dm", "Gm", "Bb", "Asus4"], 71, "epiano", "piano_sparse",
                           drums=None, lead_oct=5, rev=0.4, density=0.35, lead_gain=0.9),
    # годы идут: светлая грусть
    "time": lambda: arrange("time", 72, 4, ["C", "G", "Am", "F", "C", "G", "F", "Gsus4"], 81, "musicbox", "epiano",
                            drums="shaker", lead_oct=5, rev=0.35, density=0.45),
    # шторм и наводнение: гул и пульс
    "tense": lambda: arrange("tense", 92, 4, ["Dm", "Dm", "Bb", "A", "Dm", "Dm", "Gm", "A"], 91, None, "drone",
                             bass_on=True, drums="timpani", pad_on=True, rev=0.3, density=0.3),
    # гардероб: игриво, пиццикато и колокольчики
    "wardrobe": lambda: arrange("wardrobe", 112, 4, ["F", "Gm", "C", "F", "Bb", "C", "Am", "Dm"], 101, "glock", "pizz",
                                drums="soft", lead_oct=5, rev=0.22, density=0.6, lead_gain=0.75),
}

# ------------------------------------------------------------------ окружение (петли по 24 с)

AMB_LEN = 24.0


def _loopify(x, fade=1.5):
    """Бесшовная петля: конец плавно перетекает в начало."""
    k = int(fade * SR)
    y = x[:-k].copy()
    w = np.linspace(0, 1, k)
    y[:k] = y[:k] * w + x[-k:] * (1 - w)
    return y


def bird(rng, n):
    """Щебет: несколько коротких свистов с изгибом высоты."""
    y = np.zeros(n)
    f0 = rng.uniform(2800, 4800)
    pos = 0
    for _ in range(rng.integers(2, 6)):
        d = int(rng.uniform(0.05, 0.14) * SR)
        if pos + d >= n:
            break
        t = t_axis(d)
        f = f0 * (1 + rng.uniform(-0.25, 0.25) * np.sin(np.pi * t / t[-1]) + rng.uniform(-0.1, 0.2) * t / t[-1])
        y[pos:pos + d] += np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / t[-1]) ** 2
        pos += d + int(rng.uniform(0.02, 0.09) * SR)
    return y


def scatter(base, rng, gen, count, gain, pan_spread=0.8):
    L, R = base[0], base[1]
    n = len(L)
    for _ in range(count):
        y = gen()
        i = rng.integers(0, n)
        p = rng.uniform(-pan_spread, pan_spread)
        gl, gr = math.cos((p + 1) * math.pi / 4), math.sin((p + 1) * math.pi / 4)
        idx = (i + np.arange(len(y))) % n
        np.add.at(L, idx, y * gain * gl)
        np.add.at(R, idx, y * gain * gr)


def ambient(kind):
    rng = np.random.default_rng(hash(kind) % 2 ** 31)
    n = int((AMB_LEN + 1.5) * SR)
    base = [np.zeros(n), np.zeros(n)]

    def bed(color, lo, hi, gain, wobble=0.0, rate=0.07):
        for ch in range(2):
            y = fft_filter(noise(n, rng, color), lo=lo, hi=hi)
            y = y / (np.abs(y).max() + 1e-9)
            if wobble:
                t = t_axis(n)
                y *= 1 + wobble * np.sin(2 * np.pi * rate * t + ch * 1.3 + rng.uniform(0, 6))
            base[ch] += y * gain

    if kind == "amb_city":
        bed("brown", 40, 500, 0.35, 0.3, 0.05)           # далёкий город
        bed("pink", 300, 3000, 0.04, 0.5, 0.11)
        scatter(base, rng, lambda: bird(rng, int(0.8 * SR)), 28, 0.12)
    elif kind == "amb_home":
        bed("brown", 30, 300, 0.12)
        tick = lambda: glock(2400, 0.02, 0.5)[: int(0.05 * SR)] * np.linspace(1, 0, int(0.05 * SR))
        for s in range(int(AMB_LEN + 1.5)):                 # часы на стене
            i = int(s * SR)
            y = tick() * (0.05 if s % 2 else 0.035)
            base[0][i:i + len(y)] += y * 0.8
            base[1][i:i + len(y)] += y * 0.5
        scatter(base, rng, lambda: bird(rng, int(0.6 * SR)), 6, 0.03)
    elif kind == "amb_wind":
        bed("pink", 150, 1600, 0.5, 0.6, 0.06)
        bed("pink", 1500, 6000, 0.08, 0.8, 0.13)
    elif kind == "amb_roof_evening":
        bed("brown", 40, 400, 0.3, 0.3, 0.04)
        bed("pink", 200, 1200, 0.08, 0.6, 0.07)             # ветерок
        scatter(base, rng, lambda: bird(rng, int(0.7 * SR)), 9, 0.07)
    elif kind == "amb_roof_night":
        bed("brown", 40, 300, 0.22, 0.2, 0.03)
        def cricket():
            d = int(0.4 * SR)
            t = t_axis(d)
            return np.sin(2 * np.pi * 4300 * t) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 28 * t))) * np.sin(np.pi * t / t[-1])
        scatter(base, rng, cricket, 70, 0.025)
    elif kind == "amb_hospital":
        t = t_axis(n)
        for ch in range(2):
            base[ch] += 0.05 * (np.sin(2 * np.pi * 100 * t) + 0.5 * np.sin(2 * np.pi * 200 * t))
        bed("pink", 200, 2500, 0.07)
        def beep():
            d = int(0.12 * SR)
            return np.sin(2 * np.pi * 1000 * t_axis(d)) * env(d, a=0.005, d=0.2, s=1.0, r=0.02)
        for s in np.arange(0.5, AMB_LEN, 1.1):
            i = int(s * SR)
            y = beep() * 0.025
            base[0][i:i + len(y)] += y
            base[1][i:i + len(y)] += y * 0.6
    elif kind == "amb_rain":
        bed("pink", 400, 9000, 0.4, 0.15, 0.09)
        bed("brown", 30, 200, 0.25, 0.4, 0.05)
        def drop():
            d = int(0.03 * SR)
            return fft_filter(rng.standard_normal(d), lo=2000, hi=7000) * np.exp(-t_axis(d) * 150)
        scatter(base, rng, drop, 500, 0.06)
        def thunder():
            d = int(4.0 * SR)
            y = fft_filter(noise(d, rng, "brown"), lo=20, hi=180)
            return y / (np.abs(y).max() + 1e-9) * env(d, a=0.3, d=1.2, r=0.5)
        scatter(base, rng, thunder, 2, 0.5, 0.3)
    elif kind == "amb_sea":
        t = t_axis(n)
        for ch in range(2):
            y = fft_filter(noise(n, rng, "pink"), lo=150, hi=3000)
            y /= np.abs(y).max() + 1e-9
            swell = 0.25 + 0.75 * (0.5 + 0.5 * np.sin(2 * np.pi * t / 6.0 + ch * 0.6)) ** 3
            base[ch] += y * swell * 0.45
        scatter(base, rng, lambda: bird(rng, int(0.5 * SR)), 4, 0.04)
    st = np.stack([_loopify(base[0]), _loopify(base[1])], 1)
    return st / (np.abs(st).max() + 1e-9) * 0.7


AMBIENT = ["amb_city", "amb_home", "amb_wind", "amb_roof_evening", "amb_roof_night", "amb_hospital", "amb_rain", "amb_sea"]

# ------------------------------------------------------------------ эффекты


def step(surface, rng):
    """Шаг: короткий удар + шорох поверхности."""
    d = int(0.22 * SR)
    t = t_axis(d)
    if surface == "snow":
        y = fft_filter(rng.standard_normal(d), lo=500, hi=4000) * env(d, a=0.02, d=0.06, r=0.03)
        y += 0.5 * fft_filter(rng.standard_normal(d), lo=60, hi=400) * env(d, a=0.01, d=0.05)
    elif surface == "wood":
        y = np.sin(2 * np.pi * (140 + 60 * np.exp(-t * 40)) * t) * np.exp(-t * 35)
        y += 0.35 * fft_filter(rng.standard_normal(d), lo=300, hi=2500) * np.exp(-t * 60)
    elif surface == "tile":
        y = 0.5 * np.sin(2 * np.pi * 220 * t) * np.exp(-t * 60)
        y += 0.6 * fft_filter(rng.standard_normal(d), lo=1500, hi=7000) * np.exp(-t * 80)
    else:  # асфальт, бетон
        y = 0.6 * np.sin(2 * np.pi * (90 + 40 * np.exp(-t * 50)) * t) * np.exp(-t * 45)
        y += 0.5 * fft_filter(rng.standard_normal(d), lo=800, hi=5000) * np.exp(-t * 40)
    return y / (np.abs(y).max() + 1e-9) * 0.6


def chime(notes, spacing=0.07, inst=glock, tail=1.2, vel=0.5):
    total = int((spacing * len(notes) + tail) * SR)
    y = np.zeros(total)
    for k, nt in enumerate(notes):
        s = inst(midi(nt), 0.2, vel)
        i = int(k * spacing * SR)
        m = min(len(s), total - i)
        y[i:i + m] += s[:m]
    return reverb(y, 1.2, 0.25)


def sfx_all():
    rng = np.random.default_rng(5)
    out = {}
    for surf in ("asphalt", "wood", "tile", "snow"):
        for k in range(4):
            out[f"step_{surf}_{k + 1}"] = step(surf, rng)
    d = int(0.06 * SR)
    t = t_axis(d)
    out["ui_tap"] = np.sin(2 * np.pi * (900 + 500 * np.exp(-t * 60)) * t) * np.exp(-t * 70) * 0.5
    out["ui_open"] = chime([79, 84], 0.06, vel=0.35, tail=0.6)
    out["ui_close"] = chime([84, 77], 0.06, vel=0.3, tail=0.5)
    out["ui_confirm"] = chime([72, 76, 79, 84], 0.06, vel=0.4)
    out["ui_error"] = chime([62, 61], 0.09, inst=epiano, vel=0.4, tail=0.4)
    out["ui_hint"] = chime([88, 91], 0.05, inst=musicbox, vel=0.3, tail=0.8)
    out["ui_reward"] = chime([72, 76, 79, 84, 88, 91], 0.07, vel=0.4, tail=1.6)
    out["ui_page"] = fft_filter(rng.standard_normal(int(0.25 * SR)), lo=1500, hi=8000) * env(int(0.25 * SR), a=0.04, d=0.06, r=0.05) * 0.4
    out["equip"] = fft_filter(rng.standard_normal(int(0.3 * SR)), lo=600, hi=5000) * env(int(0.3 * SR), a=0.05, d=0.08, r=0.08) * 0.5
    out["dlg_blip"] = musicbox(midi(81), 0.05, 0.4)[: int(0.25 * SR)] * np.linspace(1, 0, int(0.25 * SR))
    out["objective"] = chime([76, 83, 88], 0.08, inst=musicbox, vel=0.35, tail=1.0)
    out["sketch"] = fft_filter(rng.standard_normal(int(0.5 * SR)), lo=2500, hi=9000) * \
        (0.3 + 0.7 * np.abs(np.sin(2 * np.pi * 6 * t_axis(int(0.5 * SR))))) * env(int(0.5 * SR), a=0.02, d=0.3, r=0.05) * 0.25
    # переезд: двойной колокол (петля 1 с)
    n = SR
    bell = np.zeros(n)
    for i0 in (0, n // 2):
        s = glock(700, 0.1, 0.6)[: n // 2] + 0.6 * glock(1050, 0.1, 0.4)[: n // 2]
        bell[i0:i0 + len(s)] += s * np.exp(-t_axis(len(s)) * 6)
    out["crossing_bell"] = bell
    # проезд поезда: нарастание и спад шума колёс со стуком на стыках
    n = int(7 * SR)
    t = t_axis(n)
    body = fft_filter(noise(n, rng, "pink"), lo=60, hi=2500)
    body = body / (np.abs(body).max() + 1e-9) * np.exp(-((t - 3.5) / 1.6) ** 2)
    clack = np.zeros(n)
    for s in np.arange(1.0, 6.0, 0.36):
        i = int(s * SR)
        c = fft_filter(rng.standard_normal(int(0.05 * SR)), lo=200, hi=2000) * np.exp(-t_axis(int(0.05 * SR)) * 60)
        clack[i:i + len(c)] += c * np.exp(-((s - 3.5) / 1.4) ** 2)
    out["train_pass"] = body * 0.8 + clack * 0.4
    out["splash"] = fft_filter(rng.standard_normal(int(0.7 * SR)), lo=300, hi=6000) * env(int(0.7 * SR), a=0.01, d=0.2, r=0.1) * 0.6
    out["door"] = step("wood", rng) * 0.8
    # игровой интерфейс 24.10: прыжок, приземление, рывок, удар, вспышка навыка, затвор, молитвы
    n = int(0.28 * SR)
    t = t_axis(n)
    out["jump"] = fft_filter(rng.standard_normal(n), lo=400, hi=3000) * env(n, a=0.03, d=0.12, r=0.05) * 0.5 \
        + 0.4 * np.sin(2 * np.pi * (300 + 500 * t / t[-1]) * t) * np.exp(-t * 14)
    out["land"] = step("asphalt", rng) * 0.9
    n = int(0.32 * SR)
    t = t_axis(n)
    out["dodge"] = fft_filter(rng.standard_normal(n), lo=700, hi=6000) * np.sin(np.pi * t / t[-1]) ** 2 * 0.6
    n = int(0.22 * SR)
    t = t_axis(n)
    out["swing"] = fft_filter(rng.standard_normal(n), lo=1200, hi=8000) * np.sin(np.pi * t / t[-1]) ** 3 * 0.6 \
        + 0.25 * glock(midi(91), 0.1, 0.3)[:n]
    out["skill"] = chime([79, 83, 86, 91, 95], 0.035, vel=0.4, tail=0.9)
    n = int(0.12 * SR)
    t = t_axis(n)
    click = np.zeros(n)
    for i0 in (0, int(0.045 * SR)):
        c = fft_filter(rng.standard_normal(int(0.02 * SR)), lo=1500, hi=9000) * np.exp(-t_axis(int(0.02 * SR)) * 250)
        click[i0:i0 + len(c)] += c
    out["shutter"] = click
    out["wish"] = chime([67, 71, 74, 79, 83, 86, 91], 0.09, inst=musicbox, vel=0.35, tail=1.4)
    out["wish_gold"] = chime([72, 79, 84, 88, 91, 96, 100], 0.08, vel=0.45, tail=2.2)
    for k, v in list(out.items()):
        out[k] = v / (np.abs(v).max() + 1e-9) * (0.9 if not k.startswith("step") else 0.7)
    return out


# ------------------------------------------------------------------ запись


def write_ogg(path, data, quality=3):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = np.clip(data, -1, 1)
    if data.ndim == 1:
        data = data[:, None]
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        tmp = f.name
    with wave.open(tmp, "wb") as w:
        w.setnchannels(data.shape[1])
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((data * 32767).astype("<i2").tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(quality), path], check=True)
    os.unlink(tmp)


def main(names):
    want = lambda n: not names or n in names
    for name, fn in MUSIC.items():
        if want(name):
            write_ogg(os.path.join(OUT, "music", name + ".ogg"), fn(), 3)
            print("music", name)
    for name in AMBIENT:
        if want(name):
            write_ogg(os.path.join(OUT, "ambient", name + ".ogg"), ambient(name), 2)
            print("ambient", name)
    if want("sfx"):
        for name, y in sfx_all().items():
            write_ogg(os.path.join(OUT, "sfx", name + ".ogg"), y, 4)
        print("sfx")


if __name__ == "__main__":
    main(sys.argv[1:])
