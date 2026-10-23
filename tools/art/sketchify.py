"""Рисунки скетчбука Кота: кадр из игры → карандашный набросок с лёгкой акварелью на бумаге.

Запуск: python3 tools/art/sketchify.py <кадр.png> <art/story/sketches/имя.png> [--warm]
Кадры снимаются сценой scenes/dev/sketch_shots.tscn (tools/capture.sh … debug_<кадр>).
"""
import sys

import numpy as np
from PIL import Image, ImageFilter

W, H = 1024, 666


def paper(w, h, rnd):
    base = np.ones((h, w, 3), np.float32) * np.array([0.985, 0.965, 0.925], np.float32)
    grain = rnd.normal(0, 1, (h // 2, w // 2)).astype(np.float32)
    grain = np.array(Image.fromarray(((grain * 18) + 128).clip(0, 255).astype(np.uint8)).resize((w, h)).filter(
        ImageFilter.GaussianBlur(0.8)), np.float32) / 255 - 0.5
    fibers = np.zeros((h, w), np.float32)
    for _ in range(260):
        y, x = rnd.integers(0, h), rnd.integers(0, w)
        ln = rnd.integers(6, 22)
        fibers[y, x:x + ln] = rnd.uniform(0.02, 0.05)
    return (base + grain[..., None] * 0.05 - fibers[..., None]).clip(0, 1)


def pencil(img):
    g = np.array(img.convert("L"), np.float32) / 255
    inv = 1 - g
    blur = np.array(Image.fromarray((inv * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(9)), np.float32) / 255
    dodge = np.clip(g / np.maximum(1 - blur, 1e-3), 0, 1)                 # «карандаш»: контуры и штриховка
    edges = np.array(img.convert("L").filter(ImageFilter.FIND_EDGES).filter(ImageFilter.GaussianBlur(0.6)), np.float32) / 255
    line = np.clip(dodge - edges * 1.8, 0, 1)
    return line ** 1.6


def hatch(h, w, rnd, dark):
    """Косая штриховка в тёмных местах — как карандашом от руки."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    s = np.sin((xx + yy * 0.6) * 0.9 + rnd.uniform(0, 6)) * 0.5 + 0.5
    return 1 - (s > 0.82) * np.clip((0.55 - dark) * 1.6, 0, 1) * 0.35


def main(src, dst, warm=False):
    rnd = np.random.default_rng(abs(hash(dst)) % 2 ** 32)
    img = Image.open(src).convert("RGB").resize((W, H), Image.LANCZOS)
    p = paper(W, H, rnd)
    line = pencil(img)
    lum = np.array(img.convert("L"), np.float32) / 255
    line = line * hatch(H, W, rnd, lum)
    # акварель: упрощённый цвет, бледнее, с «пятнами» к краям
    col = np.array(img.filter(ImageFilter.ModeFilter(9)).filter(ImageFilter.GaussianBlur(3)), np.float32) / 255
    grey = col.mean(axis=2, keepdims=True)
    col = grey + (col - grey) * 1.25
    if warm:
        col = col * np.array([1.04, 0.98, 0.9], np.float32)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    vign = 1 - (((xx / W - 0.5) ** 2 + (yy / H - 0.5) ** 2) * 2.2).clip(0, 1)
    blot = np.array(Image.fromarray((rnd.random((H // 24, W // 24)) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC),
                    np.float32) / 255
    wash = (0.42 * vign * (0.75 + 0.25 * blot))[..., None]
    out = p * (1 - wash) + p * col * wash
    out = out * (0.3 + 0.7 * line[..., None])        # графит поверх акварели
    Image.fromarray((out.clip(0, 1) * 255).astype(np.uint8)).save(dst)
    print("ok", dst)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], "--warm" in sys.argv)
