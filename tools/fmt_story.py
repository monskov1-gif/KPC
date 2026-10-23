"""Форматирование data/story/*.json: короткие объекты — одной строкой, реплики — по одной на строку.
python3 tools/fmt_story.py data/story/prologue.json"""
import json
import sys

WIDTH = 150


def dump(o, ind=0):
    flat = json.dumps(o, ensure_ascii=False)
    if len(flat) + ind <= WIDTH or not isinstance(o, (dict, list)) or not o:
        return flat
    pad = " " * (ind + 1)
    if isinstance(o, list):
        return "[\n" + ",\n".join(pad + dump(v, ind + 1) for v in o) + "\n" + " " * ind + "]"
    parts = [pad + json.dumps(k, ensure_ascii=False) + ": " + dump(v, ind + 1) for k, v in o.items()]
    return "{\n" + ",\n".join(parts) + "\n" + " " * ind + "}"


for p in sys.argv[1:]:
    d = json.load(open(p, encoding="utf-8"))
    open(p, "w", encoding="utf-8").write(dump(d) + "\n")
