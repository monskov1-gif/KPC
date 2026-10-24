"""Карта теней лица (SDF / «порог света») — как у Genshin / Zenless / Wuthering Waves (docs/MODEL_STUDY.md, «Видео»):
в каждом текселе — угол света (0 — спереди, 1 — сзади), до которого эта точка ещё освещена. Шейдер лица
(art/shaders/toon_face.gdshader) сравнивает угол солнца к лицу с порогом: тень ложится чистыми аниме-формами
(клин от носа, половина лица, «треугольник Рембрандта» под глазом на теневой стороне), а не по геометрии.

Пространство — UV лица (фронтальная проекция головы, как текстура лица из gen_faces.py): u — слева направо
(слева — правая сторона героя), v — сверху вниз в картинке. Карта для света справа от героя; для света слева
шейдер берёт её зеркально (1 − u).

Запуск: python3 tools/art/face_sdf.py → art/characters/textures/face_sdf.png
"""
import os

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "art", "characters", "textures", "face_sdf.png")
N = 512

# ориентиры в UV картинки (доли): центр лица, глаза, кончик носа, рот, подбородок
CX = 0.5
EYE_Y, NOSE_TOP, NOSE_Y, MOUTH_Y = 0.57, 0.62, 0.73, 0.83


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def build():
    v, u = np.mgrid[0:N, 0:N] / (N - 1.0)
    # основа: свет справа от героя (слева в картинке) — левая часть дольше освещена; граница «на 90°» — по середине
    # и чуть изгибается по скуле (ниже глаз уходит к дальней щеке, как у рисованных лиц)
    bend = 0.05 * smooth(EYE_Y, MOUTH_Y, v) - 0.03 * smooth(MOUTH_Y, 1.0, v)
    T = 1.0 - (u - bend)
    T = np.clip(0.5 + (T - 0.5) * 1.15, 0, 1)
    # клин тени от носа: на дальней стороне носа появляется сразу при боковом свете (порог низкий)
    rel_u = u - CX
    in_nose_y = smooth(NOSE_TOP, NOSE_TOP + 0.04, v) * (1 - smooth(NOSE_Y, NOSE_Y + 0.02, v))
    wedge_w = 0.02 + 0.05 * smooth(NOSE_TOP, NOSE_Y, v)        # клин шире к кончику носа
    nose = in_nose_y * smooth(0.0, 0.006, rel_u) * (1 - smooth(wedge_w * 0.7, wedge_w, rel_u))
    T = np.minimum(T, 1 - nose * 0.88)
    # «треугольник Рембрандта»: на теневой щеке под глазом остаётся светлый треугольник почти до 3/4 света сзади
    cy0, cy1 = EYE_Y + 0.05, NOSE_Y + 0.02
    tri_v = smooth(cy0, cy0 + 0.02, v) * (1 - smooth(cy1 - 0.02, cy1, v))
    # треугольник сужается книзу: ширина от 0.16 у глаза до 0 у носа
    k = np.clip((v - cy0) / (cy1 - cy0), 0, 1)
    left, right = CX + 0.08, CX + 0.08 + 0.17 * (1 - k)
    tri = tri_v * smooth(left - 0.01, left + 0.01, u) * (1 - smooth(right - 0.01, right + 0.01, u))
    T = np.maximum(T, tri * 0.72)
    img = Image.fromarray((np.clip(T, 0, 1) * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(2.5))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT)
    print("карта теней лица:", OUT)


if __name__ == "__main__":
    build()
