#!/usr/bin/env python3
"""Наложение силуэта тела модели на референс-лист (Meshy) — спереди и сбоку.

Оба силуэта приводятся к одной шкале по высоте «подбородок → пол» (Hc) и совмещаются по полу и по центру
торса. Печатается таблица ширины по уровням (доли Hc ниже подбородка): торс/ноги и руки отдельно;
картинка: красное — только у референса (модели не хватает), голубое — только у модели (лишнее), белое — совпадает.

  python3 tools/art/body_overlay.py --model-prefix <render> --out <png>
Рендер силуэта модели: tools/art/body_overlay.sh (Blender).
"""
import argparse
import json
import os

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
REF = os.path.join(ROOT, "art", "references", "meshy", "7A808FCC-BA29-46D7-8D10-9C0133F5F2D4.png")
# Виды на листе (x0, x1) и подбородок (y) — сняты по сетке; пол — по силуэту.
REF_VIEWS = {"front": {"x": (0, 345), "chin": 154}, "side": {"x": (335, 470), "chin": 159}}
LEVELS = [("подбородок", 0.0), ("шея", 0.05), ("плечи", 0.11), ("грудь", 0.17), ("рёбра", 0.24), ("талия", 0.31), ("пояс", 0.37),
          ("бёдра/таз", 0.43), ("пах", 0.48), ("бедро", 0.56), ("над коленом", 0.66), ("колено", 0.72),
          ("икра", 0.8), ("голень", 0.88), ("щиколотка", 0.95)]
HAIR_LEVELS = [-0.27, -0.24, -0.21, -0.18, -0.15, -0.12, -0.09, -0.06, -0.03, 0.0, 0.03, 0.06]


def ref_mask(view):
    im = np.asarray(Image.open(REF).convert("RGB")).astype(np.float32)
    x0, x1 = REF_VIEWS[view]["x"]
    sub = im[:, x0:x1]
    lum = sub.mean(axis=2)
    sat = sub.max(axis=2) - sub.min(axis=2)
    m = (lum > 82) | (sat > 40)
    m[:, :] &= np.arange(m.shape[0])[:, None] < 716        # ниже — следующий ряд картинок листа
    return m


def runs(row):
    r, start = [], None
    for i, v in enumerate(row):
        if v and start is None:
            start = i
        elif not v and start is not None:
            r.append((start, i))
            start = None
    if start is not None:
        r.append((start, len(row)))
    return [q for q in r if q[1] - q[0] > 1]


def profile(m, chin, floor, cx):
    Hc = floor - chin
    out = {}
    for name, t in LEVELS:
        y = int(round(chin + t * Hc))
        rs = runs(m[y])
        body = [q for q in rs if abs((q[0] + q[1]) / 2 - cx) < 0.13 * Hc]
        arms = [q for q in rs if q not in body]
        bw = sum(q[1] - q[0] for q in body) / Hc
        lw = (np.mean([q[1] - q[0] for q in body]) / Hc) if len(body) == 2 else None
        aw = (np.mean([q[1] - q[0] for q in arms]) / Hc) if arms else None
        if arms:
            # толщина руки поперёк её оси: срез ×cos(наклона), наклон — по центру руки на ±1% Hc
            q = max(arms, key=lambda r: r[1] - r[0])
            side = 1 if (q[0] + q[1]) / 2 > cx else -1
            def acen(yy):
                c = [((a + b) / 2) for a, b in runs(m[yy]) if abs((a + b) / 2 - cx) >= 0.13 * Hc and ((a + b) / 2 - cx) * side > 0]
                return c[0] if c else None
            d = int(0.01 * Hc)
            c0, c1 = acen(y - d), acen(y + d)
            if c0 is not None and c1 is not None:
                aw = (q[1] - q[0]) / Hc * float(np.cos(np.arctan2(c1 - c0, 2 * d)))
        span = (max(q[1] for q in rs) - min(q[0] for q in rs)) / Hc if rs else 0
        # края силуэта относительно центра торса (для профиля: перед — «−», спина — «+»)
        ed = ((min(q[0] for q in body) - cx) / Hc, (max(q[1] for q in body) - cx) / Hc) if body else (0, 0)
        out[name] = {"body": bw, "leg": lw, "arm": aw, "span": span, "edge": ed}
    return out


def floor_of(m):
    ys = np.where(m.any(axis=1))[0]
    return ys.max()


def centre(m, chin, floor, view):
    """Центр торса: спереди — середина между коленями (руки и их асимметрия не влияют), сбоку — середина
    самого широкого участка на уровне груди."""
    if view == "front":
        y = int(chin + 0.72 * (floor - chin))
        rs = sorted(runs(m[y]), key=lambda r: r[1] - r[0])[-2:]
        if len(rs) == 2:
            return (min(q[0] for q in rs) + max(q[1] for q in rs)) / 2
    y = int(chin + 0.2 * (floor - chin))
    rs = runs(m[y])
    q = max(rs, key=lambda r: r[1] - r[0])
    return (q[0] + q[1]) / 2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model-prefix", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    meta = json.load(open(a.model_prefix + ".json"))
    panels = []
    report = []
    for view in ("front", "side"):
        rm = ref_mask(view)
        rchin, rfloor = REF_VIEWS[view]["chin"], floor_of(rm)
        rcx = centre(rm, rchin, rfloor, view)
        mm = np.asarray(Image.open(f"{a.model_prefix}_{view}.png").convert("L")) > 128
        mchin, mfloor = meta["chin_px"], floor_of(mm)
        mcx = centre(mm, mchin, mfloor, view)
        rp, mp = profile(rm, rchin, rfloor, rcx), profile(mm, mchin, mfloor, mcx)
        report.append((view, rp, mp))
        # Наложение в масштабе референса.
        k = (rfloor - rchin) / (mfloor - mchin)
        W = rm.shape[1] + 120
        Hh = rm.shape[0]
        img = Image.fromarray((mm * 255).astype(np.uint8)).resize((int(mm.shape[1] * k), int(mm.shape[0] * k)), Image.BILINEAR)
        mm2 = np.zeros((Hh, W), bool)
        arr = np.asarray(img) > 128
        ox = int(W / 2 - mcx * k)
        oy = int(rfloor - mfloor * k)
        ys, xs = np.nonzero(arr)
        ys2, xs2 = ys + oy, xs + ox
        ok = (ys2 >= 0) & (ys2 < Hh) & (xs2 >= 0) & (xs2 < W)
        mm2[ys2[ok], xs2[ok]] = True
        rm2 = np.zeros((Hh, W), bool)
        rx = int(W / 2 - rcx)
        rm2[:, max(0, rx):max(0, rx) + rm.shape[1]] = rm[:, :min(rm.shape[1], W - max(0, rx))]
        rgb = np.zeros((Hh, W, 3), np.uint8) + 30
        rgb[rm2 & ~mm2] = (230, 60, 60)
        rgb[mm2 & ~rm2] = (60, 210, 230)
        rgb[rm2 & mm2] = (235, 235, 235)
        rgb[rchin] = (255, 220, 0)
        panels.append(Image.fromarray(rgb))
    out = Image.new("RGB", (sum(p.width for p in panels), panels[0].height), (30, 30, 30))
    x = 0
    for p in panels:
        out.paste(p, (x, 0))
        x += p.width
    out.crop((0, 100, out.width, out.height)).save(a.out)
    for view, rp, mp in report:
        print(f"== {view} (доли Hc = подбородок→пол; модель / реф; >0 — модель шире)")
        for name, _t in LEVELS:
            r, m = rp[name], mp[name]
            line = f"{name:12s} тело {m['body']:.3f}/{r['body']:.3f} ({m['body'] - r['body']:+.3f})"
            if r["leg"] and m["leg"]:
                line += f"  нога {m['leg']:.3f}/{r['leg']:.3f} ({m['leg'] - r['leg']:+.3f})"
            if r["arm"] and m["arm"]:
                line += f"  рука {m['arm']:.3f}/{r['arm']:.3f} ({m['arm'] - r['arm']:+.3f})"
            if view == "side":
                line += f"  перед {m['edge'][0]:+.3f}/{r['edge'][0]:+.3f}  спина {m['edge'][1]:+.3f}/{r['edge'][1]:+.3f}"
            print(line)
    # Причёска: силуэт с волосами и ушами выше подбородка (t < 0 — выше), края от центра торса.
    for view in ("front", "side"):
        hp = f"{a.model_prefix}_{view}_hair.png"
        if not os.path.exists(hp):
            continue
        rm = ref_mask(view)
        rchin, rfloor = REF_VIEWS[view]["chin"], floor_of(rm)
        rcx = centre(rm, rchin, rfloor, view)
        mb = np.asarray(Image.open(f"{a.model_prefix}_{view}.png").convert("L")) > 128
        mchin, mfloor = meta["chin_px"], floor_of(mb)
        mcx = centre(mb, mchin, mfloor, view)
        mh = np.asarray(Image.open(hp).convert("L")) > 128
        rH, mH = rfloor - rchin, mfloor - mchin
        print(f"== причёска, {view}: края копны от центра (доли Hc; модель / реф)")
        for t in HAIR_LEVELS:
            ry, my = int(round(rchin + t * rH)), int(round(mchin + t * mH))
            def ed(m, y, cx, H):
                if y < 0:
                    return None
                xs = np.nonzero(m[y])[0]
                return ((xs.min() - cx) / H, (xs.max() - cx) / H) if len(xs) else None
            r, m = ed(rm, ry, rcx, rH), ed(mh, my, mcx, mH)
            fmt = lambda e: f"{e[0]:+.3f}…{e[1]:+.3f} (ш {e[1] - e[0]:.3f})" if e else "—"
            print(f"  t={t:+.2f}  {fmt(m):34s} / {fmt(r)}")
        # картинка: силуэт с волосами поверх рефа (голова крупно)
        k = rH / mH
        img = Image.fromarray((mh * 255).astype(np.uint8)).resize((int(mh.shape[1] * k), int(mh.shape[0] * k)), Image.BILINEAR)
        arr = np.asarray(img) > 128
        W, Hh = rm.shape[1] + 120, rm.shape[0]
        mm2 = np.zeros((Hh, W), bool)
        ox, oy = int(W / 2 - mcx * k), int(rfloor - mfloor * k)
        ys, xs = np.nonzero(arr)
        ys2, xs2 = ys + oy, xs + ox
        ok = (ys2 >= 0) & (ys2 < Hh) & (xs2 >= 0) & (xs2 < W)
        mm2[ys2[ok], xs2[ok]] = True
        rm2 = np.zeros((Hh, W), bool)
        rx = int(W / 2 - rcx)
        rm2[:, max(0, rx):max(0, rx) + rm.shape[1]] = rm[:, :min(rm.shape[1], W - max(0, rx))]
        rgb = np.zeros((Hh, W, 3), np.uint8) + 30
        rgb[rm2 & ~mm2] = (230, 60, 60)
        rgb[mm2 & ~rm2] = (60, 210, 230)
        rgb[rm2 & mm2] = (235, 235, 235)
        top = max(0, int(rchin - 0.32 * rH))
        Image.fromarray(rgb[top:int(rchin + 0.12 * rH)]).resize((W * 3, (int(rchin + 0.12 * rH) - top) * 3), Image.NEAREST).save(
            a.out.replace(".png", f"_hair_{view}.png"))
    print("Наложение:", a.out)


if __name__ == "__main__":
    main()
