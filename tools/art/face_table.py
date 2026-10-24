"""Параметры лица персонажа из tools/art/face_params.json с наследованием «_from» (пресеты баз тела:
teen_m, teen_f, adult_m, adult_f, child). Чистый Python — импортируют и Blender (build_characters.py),
и генератор текстур (gen_faces.py)."""
import copy
import json
import os

PATH = os.path.join(os.path.dirname(__file__), "face_params.json")


def load():
    with open(PATH, encoding="utf-8") as f:
        return json.load(f)


def _merge(dst, src):
    for k, v in src.items():
        if k == "_from":
            continue
        if isinstance(v, dict) and isinstance(dst.get(k), dict):
            _merge(dst[k], v)
        else:
            dst[k] = copy.deepcopy(v)


def resolve(table, key, fallback=None):
    """default ← цепочка «_from» ← сам ключ (вложенные словари сливаются). Нет ключа — берётся fallback."""
    chain = []
    k = key if key in table else fallback
    while k is not None and k in table and k not in chain:
        chain.append(k)
        k = table[k].get("_from")
    out = copy.deepcopy(table["default"])
    for k in reversed(chain):
        _merge(out, table[k])
    return out
