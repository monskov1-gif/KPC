#!/usr/bin/env python3
"""Наложение референса на рендер модели по ориентирам — проверка «1 в 1».

Как это делает пользователь: реф подгоняется к рендеру по линии челюсти. Здесь то же, но точно:
  • рендер снимается сценой scenes/dev/character_lineup.tscn (debug_ref_*), рядом пишется JSON с экранными
    координатами ориентиров модели (пустые узлы lm_* в .glb);
  • реф совмещается с рендером преобразованием подобия (сдвиг, поворот, масштаб) по двум опорным точкам
    (anchors: подбородок и видимый глаз);
  • для остальных ориентиров печатается расхождение в пикселях и в долях U (U — расстояние глаз–подбородок).

Запуск:
  GODOT=… tools/art/ref_overlay.sh portrait kot          # снять рендер и собрать наложение
  python3 tools/art/ref_overlay.py --render r.png --lm r.json --view portrait --out o.png
Выход: картинка из 4 панелей (рендер | реф | 50/50 | контуры рефа поверх рендера + стрелки ошибок) и таблица.
"""
import argparse
import json
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
REF_LM = os.path.join(ROOT, "art", "references", "characters", "16_kot_landmarks.json")


def similarity(src, dst, rotate=False):
    """Комплексное k и t: dst = k·src + t. Без поворота (по умолчанию): масштаб — по вертикальному
    расстоянию между опорами (глаз–подбородок), сдвиг — по первой опоре (подбородок). Оба кадра вертикальны,
    поэтому поворот только маскировал бы ошибки положения глаза."""
    a1, a2 = complex(*src[0]), complex(*src[1])
    b1, b2 = complex(*dst[0]), complex(*dst[1])
    if rotate:
        k = (b2 - b1) / (a2 - a1)
    else:
        k = complex((b2 - b1).imag / (a2 - a1).imag, 0)
    return k, b1 - k * a1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--render", required=True)
    ap.add_argument("--lm", required=True)
    ap.add_argument("--view", default="portrait")
    ap.add_argument("--ref-lm", default=REF_LM)
    ap.add_argument("--out", required=True)
    ap.add_argument("--rotate", action="store_true", help="разрешить поворот при совмещении")
    a = ap.parse_args()

    spec = json.load(open(a.ref_lm, encoding="utf-8"))
    view = spec["views"][a.view]
    ref = Image.open(os.path.join(os.path.dirname(a.ref_lm), spec["image"])).convert("RGB")
    ren = Image.open(a.render).convert("RGB")
    mlm = json.load(open(a.lm, encoding="utf-8"))
    rpts = view["points"]
    anc = view["anchors"]
    missing = [n for n in anc if n not in mlm]
    if missing:
        raise SystemExit(f"в рендере нет опорных ориентиров: {missing}")
    k, t = similarity([rpts[n] for n in anc], [mlm[n] for n in anc], a.rotate)
    # Перенос рефа в кадр рендера (PIL ждёт обратное отображение: выход → вход).
    ki = 1 / k
    c0 = -ki * t
    aff = (ki.real, -ki.imag, c0.real, ki.imag, ki.real, c0.imag)
    warped = ref.transform(ren.size, Image.AFFINE, aff, resample=Image.BICUBIC, fillcolor=(40, 40, 46))

    def to_ren(p):
        z = k * complex(*p) + t
        return (z.real, z.imag)
    u = abs(mlm[anc[0]][1] - mlm[anc[1]][1])
    rows = []
    for name, p in rpts.items():
        rp = to_ren(p)
        if name in mlm and not (name == anc[0]):
            mp = mlm[name]
            d = math.dist(rp, mp)
            rows.append((name, rp, mp, d, d / u, (mp[0] - rp[0]) / u, (mp[1] - rp[1]) / u))
        else:
            rows.append((name, rp, None, None, None, None, None))

    W, H = ren.size
    blend = Image.blend(ren, warped, 0.5)
    edges = ImageOps.autocontrast(warped.convert("L").filter(ImageFilter.FIND_EDGES))
    edges = edges.point(lambda v: 255 if v > 60 else 0)
    marked = ren.copy()
    red = Image.new("RGB", ren.size, (230, 40, 60))
    marked = Image.composite(red, marked, edges)
    d = ImageDraw.Draw(marked)
    for name, rp, mp, dist, du, dx, dy in rows:
        d.ellipse((rp[0] - 5, rp[1] - 5, rp[0] + 5, rp[1] + 5), outline=(230, 40, 60), width=3)
        if mp:
            d.ellipse((mp[0] - 5, mp[1] - 5, mp[0] + 5, mp[1] + 5), fill=(30, 200, 90))
            d.line((mp[0], mp[1], rp[0], rp[1]), fill=(255, 220, 0), width=2)
            d.text((mp[0] + 7, mp[1] - 7), f"{name} {du:.2f}U", fill=(20, 20, 20))
    out = Image.new("RGB", (W * 4, H), (255, 255, 255))
    for i, im in enumerate((ren, warped, blend, marked)):
        out.paste(im, (i * W, 0))
    od = ImageDraw.Draw(out)
    for i, title in enumerate(("модель", "референс (совмещён)", "наложение 50/50", "контур рефа + ошибки")):
        od.rectangle((i * W, 0, i * W + 260, 22), fill=(255, 255, 255))
        od.text((i * W + 6, 5), title, fill=(0, 0, 0))
    out.save(a.out)
    print(f"U (глаз–подбородок по вертикали на рендере) = {u:.1f} px; опоры: {', '.join(anc)}")
    print(f"{'ориентир':16s} {'ошибка,U':>9s} {'dx,U':>7s} {'dy,U':>7s}   (dx>0 — модель правее рефа, dy>0 — ниже)")
    total = []
    for name, rp, mp, dist, du, dx, dy in rows:
        if name == anc[0]:
            continue
        if mp is None:
            print(f"{name:16s} {'нет у модели':>9s}")
            continue
        total.append(du)
        print(f"{name:16s} {du:9.2f} {dx:7.2f} {dy:7.2f}")
    if total:
        print(f"средняя ошибка: {sum(total) / len(total):.2f} U; худшая: {max(total):.2f} U")


if __name__ == "__main__":
    main()
