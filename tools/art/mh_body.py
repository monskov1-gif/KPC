"""Тело персонажа на основе открытой базовой модели MakeHuman (CC0, tools/art/basemesh/, см. README там).

Не «с нуля»: берём готовую анатомичную сетку (кисти с пальцами, стопы, ключицы, мышцы), смешиваем
открытые морф-цели (пол, возраст «подросток» = смесь young/child, худощавость, грудь) и переводим
в пропорции персонажа: шея и таз — на заданные высоты, ноги длиннее (аниме). Голову базовой модели
срезаем — у нас своя голова (build_head), шея продлевается внутрь неё.

Чистый Python (без bpy): parse → apply_targets → to_character. Сборку в Blender делает build_characters.py.
"""
import os

BASE = os.path.join(os.path.dirname(__file__), "basemesh")


def load_base():
    """Вершины (MakeHuman: Y вверх, лицо +Z, дециметры), грани группы body, группы суставов."""
    vs, faces, groups = [], [], {}
    cur = None
    for line in open(os.path.join(BASE, "base.obj"), encoding="utf-8"):
        if line.startswith("v "):
            vs.append([float(t) for t in line.split()[1:4]])
        elif line.startswith("g "):
            cur = line.split()[1]
        elif line.startswith("f "):
            idx = [int(t.split("/")[0]) - 1 for t in line.split()[1:]]
            if cur == "body":
                faces.append(idx)
            else:
                groups.setdefault(cur, set()).update(idx)
    return vs, faces, groups


def apply_target(vs, name, w):
    if not w:
        return
    for line in open(os.path.join(BASE, "targets", name + ".target"), encoding="utf-8"):
        if not line.strip() or line[0] == "#":
            continue
        i, dx, dy, dz = line.split()
        v = vs[int(i)]
        v[0] += float(dx) * w
        v[1] += float(dy) * w
        v[2] += float(dz) * w


def shape(sex, teen=0.45, thin=0.7, bust=0.0):
    """sex: male|female; teen: доля «child» в возрасте (0 — взрослый young); thin: к худощавому; bust: грудь 0..1."""
    vs, faces, groups = load_base()
    g = sex
    apply_target(vs, f"macrodetails_caucasian-{g}-young", 1 - teen)
    apply_target(vs, f"macrodetails_caucasian-{g}-child", teen)
    apply_target(vs, f"macrodetails_universal-{g}-young-averagemuscle-minweight", (1 - teen) * thin)
    apply_target(vs, f"macrodetails_universal-{g}-child-averagemuscle-minweight", teen * thin)
    apply_target(vs, f"macrodetails_proportions_{g}-young-averagemuscle-averageweight-idealproportions", 1.0)
    if sex == "female":
        if bust >= 0:
            apply_target(vs, "breast_female-young-averagemuscle-averageweight-maxcup-averagefirmness", bust)
        else:
            apply_target(vs, "breast_female-young-averagemuscle-averageweight-mincup-averagefirmness", -bust)
    return vs, faces, groups


def joint(vs, groups, name):
    idx = groups["joint-" + name]
    return [sum(vs[i][k] for i in idx) / len(idx) for k in range(3)]


def lower_arms(vs, groups, deg):
    """Опустить руки из А-позы базовой модели (≈43° от вертикали) на deg градусов: поворот вокруг плеча,
    вес плавно растёт от подмышки к локтю — без изломов у плеча."""
    import math
    for sx, side in ((1, "l"), (-1, "r")):
        sh = joint(vs, groups, f"{side}-shoulder")
        hand = joint(vs, groups, f"{side}-hand")
        ax = [hand[0] - sh[0], hand[1] - sh[1]]
        L = math.hypot(*ax)
        ax = [ax[0] / L, ax[1] / L]
        a = math.radians(deg) * sx          # к телу: левая рука (+X) вращается по часовой (вниз)
        ca, sa = math.cos(-a), math.sin(-a)
        joints = {i for g, idx in groups.items() if g.startswith(f"joint-{side}-") for i in idx}
        for i, v in enumerate(vs):
            dx, dy = v[0] - sh[0], v[1] - sh[1]
            t = dx * ax[0] + dy * ax[1]
            perp = abs(-dx * ax[1] + dy * ax[0])
            if v[0] * sx < 0.9 or t < -0.4 or perp > 1.3 + max(0.0, t - L) * 0.6:
                if i not in joints:
                    continue
            w = 1.0 if i in joints else min(1.0, max(0.0, (t + 0.4) / 1.4))
            w = w * w * (3 - 2 * w)
            c, s_ = math.cos(-a * w), math.sin(-a * w)
            v[0], v[1] = sh[0] + dx * c - dy * s_, sh[1] + dx * s_ + dy * c


def _mat_mul(A, B):
    return [[sum(A[i][k] * B[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def _about(R, c):
    """4×4: поворот R (3×3) вокруг точки c."""
    M = [[R[i][0], R[i][1], R[i][2], 0.0] for i in range(3)] + [[0.0, 0.0, 0.0, 1.0]]
    for i in range(3):
        M[i][3] = c[i] - sum(R[i][k] * c[k] for k in range(3))
    return M


def _apply(M, v):
    return [M[i][0] * v[0] + M[i][1] * v[1] + M[i][2] * v[2] + M[i][3] for i in range(3)]


def _rot_between(a, b, frac=1.0):
    import math
    a, b = _norm(a), _norm(b)
    ax = _cross(a, b)
    ang = math.acos(max(-1.0, min(1.0, _dot(a, b))))
    if ang < 1e-6 or _dot(ax, ax) < 1e-12:
        return [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    return _rot(ax, ang * frac)


class Skeleton:
    """Открытый скелет MakeHuman (default.mhskel, CC0) с весами (default_weights.mhw, CC0).
    Поза — линейное скиннинг-смешивание по весам: плечи и запястья гнутся плавно, без надломов."""

    def __init__(self, vs):
        import json
        sk = json.load(open(os.path.join(BASE, "default.mhskel"), encoding="utf-8"))
        wt = json.load(open(os.path.join(BASE, "default_weights.mhw"), encoding="utf-8"))["weights"]
        self.vs = vs
        self.bones = sk["bones"]
        J = {k: [sum(vs[i][c] for i in idx) / len(idx) for c in range(3)] for k, idx in sk["joints"].items()}
        self.head = {b: J[d["head"]] for b, d in self.bones.items()}
        self.tail = {b: J[d["tail"]] for b, d in self.bones.items()}
        self.local = {}                     # кость → 3×3 поворот в мировых осях покоя
        self.weights = {}                   # вершина → [(кость, вес)]
        for b, lst in wt.items():
            for i, w in lst:
                self.weights.setdefault(i, []).append((b, w))

    def world(self):
        M = {}

        def get(b):
            if b in M:
                return M[b]
            par = self.bones[b]["parent"]
            base = get(par) if par else [[1.0 if i == j else 0.0 for j in range(4)] for i in range(4)]
            R = self.local.get(b)
            M[b] = _mat_mul(base, _about(R, self.head[b])) if R else base
            return M[b]
        for b in self.bones:
            get(b)
        return M

    def posed_joint(self, b, which="head"):
        M = self.world()[b]
        par = self.bones[b]["parent"]
        p = self.head[b] if which == "head" else self.tail[b]
        return _apply(M if which == "tail" else (self.world()[par] if par else M), p) if which == "head" else _apply(M, p)

    def rotate(self, b, R):
        """Повернуть кость b (с детьми) на R, заданный в ТЕКУЩИХ мировых осях позы, вокруг её текущей головы.
        Перевод в локальную форму: L ← Rpᵀ·R·Rp·L, где Rp — поворот родителя."""
        par = self.bones[b]["parent"]
        if par:
            Mp = self.world()[par]
            Rp = [[Mp[i][j] for j in range(3)] for i in range(3)]
        else:
            Rp = [[1.0 if i == j else 0.0 for j in range(3)] for i in range(3)]
        mm = lambda A, B: [[sum(A[i][k] * B[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
        RpT = [[Rp[j][i] for j in range(3)] for i in range(3)]
        Lw = mm(mm(RpT, R), Rp)
        cur = self.local.get(b)
        self.local[b] = Lw if cur is None else mm(Lw, cur)

    def apply(self, groups):
        """Перенести позу на вершины и на группы суставов (joint-*) — у них веса берутся от ближайшей вершины тела."""
        M = self.world()
        new = []
        for i, v in enumerate(self.vs):
            ws = self.weights.get(i)
            if not ws:
                new.append(list(v))
                continue
            tot = sum(w for _, w in ws)
            acc = [0.0, 0.0, 0.0]
            for b, w in ws:
                q = _apply(M[b], v)
                for c in range(3):
                    acc[c] += q[c] * w / tot
            new.append(acc)
        # вершины суставов-помощников (без весов): переносим матрицей кости, чья голова в покое ближе всего
        # (а не по ближайшей вершине кожи — для таза это была бы вершина бедра, и сустав «уезжал» с ногой)
        heads = list(self.head.items())
        for g, idx in groups.items():
            if not g.startswith("joint-"):
                continue
            c = [sum(self.vs[i][k] for i in idx) / len(idx) for k in range(3)]
            b = min(heads, key=lambda kv: sum((kv[1][k] - c[k]) ** 2 for k in range(3)))[0]
            par = self.bones[b]["parent"]
            Mb = M[par] if par else None
            for i in idx:
                if i in self.weights:
                    continue
                new[i] = _apply(Mb, self.vs[i]) if Mb else list(self.vs[i])
        for i, v in enumerate(new):
            self.vs[i][:] = v


def pose_arms(vs, groups, down_deg=15.0, elbow_bend=22.0, finger_curl=14.0, legs_in=3.0):
    """Руки вдоль тела как на Meshy-листе: плечо опускается, предплечье выпрямляется, кисть — по оси
    предплечья ладонью к бедру. Через скелет и веса MakeHuman (CC0)."""
    import math
    sk = Skeleton(vs)
    for sx, S in ((1, "L"), (-1, "R")):
        ua, la, wr = f"upperarm01.{S}", f"lowerarm01.{S}", f"wrist.{S}"
        # опускание делим: треть — плечо (shoulder01), две трети — плечевая кость (без сжатия подмышки)
        sk.rotate(f"shoulder01.{S}", _rot([0, 0, 1], -math.radians(down_deg / 6) * sx))
        sk.rotate(ua, _rot([0, 0, 1], -math.radians(down_deg * 5 / 6) * sx))
        sk.rotate(ua, _rot([1, 0, 0], math.radians(14)))          # рука чуть назад — в профиль не вынесена вперёд
        M = sk.world()
        sh = _apply(M[ua], sk.head[ua])
        el = _apply(M[la], sk.head[la])
        hd = _apply(M[wr], sk.head[wr])
        up = _norm(_sub(el, sh))
        want = _norm([up[0], up[1], up[2] + math.sin(math.radians(elbow_bend))])
        sk.rotate(la, _rot_between(_sub(hd, el), want))
        # кисть целиком (запястье → кончик среднего пальца) — по оси предплечья
        M = sk.world()
        el = _apply(M[la], sk.head[la])
        hd = _apply(M[wr], sk.head[wr])
        tip = _apply(M[f"finger3-3.{S}"], sk.tail[f"finger3-3.{S}"])
        fdir = _norm(_sub(hd, el))
        sk.rotate(wr, _rot_between(_sub(tip, hd), fdir))
        # ладонью к бедру: линия костяшек (указательный → мизинец) идёт спереди назад (+Z MakeHuman)
        M = sk.world()
        f2 = _apply(M[f"finger2-1.{S}"], sk.head[f"finger2-1.{S}"])
        f5 = _apply(M[f"finger5-1.{S}"], sk.head[f"finger5-1.{S}"])
        acr = _sub(f2, f5)
        acr = _sub(acr, [fdir[c] * _dot(acr, fdir) for c in range(3)])
        fwd = [0.0, 0.0, 1.0]
        fwd = _sub(fwd, [fdir[c] * _dot(fwd, fdir) for c in range(3)])
        # поворот вокруг оси предплечья — делим на две кости-скрутки предплечья и запястье (без «фантика»)
        import math as _m
        a_ = _m.acos(max(-1.0, min(1.0, _dot(_norm(acr), _norm(fwd)))))
        sgn = 1.0 if _dot(_cross(acr, fwd), fdir) >= 0 else -1.0
        for bn in (la, f"lowerarm02.{S}", wr):
            sk.rotate(bn, _rot(fdir, sgn * a_ / 3))
        # пальцы слегка согнуты (у Meshy-листа кисть расслаблена, пальцы сомкнуты)
        for k in range(2, 6):
            for j in (1, 2, 3):
                bn = f"finger{k}-{j}.{S}"
                M = sk.world()
                h = _apply(M[bn], sk.head[bn])
                t = _apply(M[bn], sk.tail[bn])
                d = _norm(_sub(t, h))
                f2 = _apply(M[f"finger2-1.{S}"], sk.head[f"finger2-1.{S}"])
                f5 = _apply(M[f"finger5-1.{S}"], sk.head[f"finger5-1.{S}"])
                ax = _norm(_sub(f2, f5))
                sk.rotate(bn, _rot(ax, math.radians(finger_curl) * -sx * (1 if j == 1 else 0.7)))
        # большой палец — к ладони (не оттопырен крючком)
        for j in (2, 3):
            bn = f"finger1-{j}.{S}"
            M = sk.world()
            f2 = _apply(M[f"finger2-1.{S}"], sk.head[f"finger2-1.{S}"])
            th = _apply(M[bn], sk.head[bn])
            tt = _apply(M[bn], sk.tail[bn])
            ax = _norm(_cross(_sub(tt, th), _sub(f2, th)))
            sk.rotate(bn, _rot(ax, math.radians(20)))
    # ноги: стойка ровнее (у базы ноги расставлены «Λ»), стопы обратно параллельно полу
    for sx, S in ((1, "L"), (-1, "R")):
        sk.rotate(f"upperleg01.{S}", _rot([0, 0, 1], -math.radians(legs_in) * sx))
        sk.rotate(f"foot.{S}", _rot([0, 0, 1], math.radians(legs_in) * sx))
    sk.apply(groups)
    return sk


def _rot(axis, ang):
    import math
    x, y, z = axis
    n = math.sqrt(x * x + y * y + z * z) or 1.0
    x, y, z = x / n, y / n, z / n
    c, s_ = math.cos(ang), math.sin(ang)
    C = 1 - c
    return [[c + x * x * C, x * y * C - z * s_, x * z * C + y * s_],
            [y * x * C + z * s_, c + y * y * C, y * z * C - x * s_],
            [z * x * C - y * s_, z * y * C + x * s_, c + z * z * C]]


def _sub(a, b):
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def _norm(a):
    n = _dot(a, a) ** 0.5 or 1.0
    return [a[0] / n, a[1] / n, a[2] / n]


def straighten_arms(vs, groups, elbow_bend=8.0):
    """Предплечье — продолжение плеча (почти прямая рука вдоль тела, лёгкий изгиб elbow_bend°),
    кисть — вдоль предплечья, ладонью к бедру. Вершины вращаются вокруг локтя/запястья с плавным весом."""
    import math
    for sx, side in ((1, "l"), (-1, "r")):
        J = lambda n: joint(vs, groups, f"{side}-{n}")
        sh, el, hd, tip = J("shoulder"), J("elbow"), J("hand"), J("finger-3-4")
        joints = {i for g, idx in groups.items() if g.startswith(f"joint-{side}-") for i in idx}
        def seg_d(v, a, b):
            ab = _sub(b, a)
            t = max(0.0, min(1.0, _dot(_sub(v, a), ab) / (_dot(ab, ab) or 1.0)))
            q = [a[k] + ab[k] * t for k in range(3)]
            return _dot(_sub(v, q), _sub(v, q)) ** 0.5
        # только сама рука: близко к цепочке плечо→локоть→кисть→кончик пальцев (не бёдра рядом)
        tips = [J(f"finger-{k}-4") for k in range(1, 6)] + [J(f"finger-{k}-1") for k in range(1, 6)]
        arm = [i for i, v in enumerate(vs) if v[0] * sx > 1.6 and
               min([seg_d(v, el, hd), seg_d(v, sh, el) + 0.3] + [seg_d(v, hd, q) for q in tips]) < 0.75]

        def turn(pivot, cur_dir, want_dir, start, span, idx_set):
            axis = _cross(cur_dir, want_dir)
            ang = math.acos(max(-1.0, min(1.0, _dot(_norm(cur_dir), _norm(want_dir)))))
            if ang < 1e-4:
                return
            d = _norm(cur_dir)
            for i in idx_set:
                v = vs[i]
                rel = _sub(v, pivot)
                t = _dot(rel, d)
                w = 1.0 if i in joints and t > 0 else min(1.0, max(0.0, (t - start) / span))
                if w <= 0:
                    continue
                w = w * w * (3 - 2 * w)
                R = _rot(axis, ang * w)
                v[0], v[1], v[2] = (pivot[0] + R[0][0] * rel[0] + R[0][1] * rel[1] + R[0][2] * rel[2],
                                    pivot[1] + R[1][0] * rel[0] + R[1][1] * rel[1] + R[1][2] * rel[2],
                                    pivot[2] + R[2][0] * rel[0] + R[2][1] * rel[1] + R[2][2] * rel[2])
        up = _norm(_sub(el, sh))
        # целевое направление предплечья: плечо, чуть согнутое вперёд
        want = _norm([up[0], up[1], up[2] + math.sin(math.radians(elbow_bend))])
        turn(el, _sub(hd, el), want, -0.35, 0.7, set(arm) | joints)
        hd, tip, el = J("hand"), J("finger-3-4"), J("elbow")
        fdir = _norm(_sub(hd, el))
        turn(hd, _sub(tip, hd), fdir, -0.2, 0.45, {i for i in set(arm) | joints if _dot(_sub(vs[i], hd), fdir) > -0.6})


LEG_BONES = ("upperleg", "lowerleg", "foot", "toe")


ARM_BONES = ("upperarm", "lowerarm", "wrist", "finger", "metacarpal")
FOOT_BONES = ("foot", "toe")


def bone_share(sk, prefixes):
    out = {}
    for i, ws in sk.weights.items():
        tot = sum(w for _, w in ws) or 1.0
        out[i] = sum(w for b, w in ws if b.startswith(prefixes)) / tot
    return out


def lengthen(vs, groups, sk, arm=1.2, foot=1.12, hand=1.0):
    """Удлинить руки (от плечевого сустава вдоль оси руки) и стопы (от голеностопа вперёд) по весам скелета —
    аниме-пропорции Meshy-листа: кончики пальцев ниже промежности, стопа длиннее."""
    aw = bone_share(sk, ARM_BONES)
    fw = bone_share(sk, FOOT_BONES)
    hw = bone_share(sk, ("wrist", "finger", "metacarpal"))
    jh = {i: 1.0 for g, idx in groups.items() if g.startswith("joint-") and any(t in g for t in ("finger", "hand-2", "hand-3")) for i in idx}
    jw = {}
    for g, idx in groups.items():
        if g.startswith("joint-"):
            n = g[6:]
            for i in idx:
                jw[i] = (1.0 if any(t in n for t in ("elbow", "hand", "finger")) else 0.0,
                         1.0 if any(t in n for t in ("toe", "foot")) else 0.0)
    for sx, side in ((1, "l"), (-1, "r")):
        sh = joint(vs, groups, f"{side}-shoulder")
        hd = joint(vs, groups, f"{side}-hand")
        d = _norm(_sub(hd, sh))
        an = joint(vs, groups, f"{side}-ankle")
        hd2 = [hd[c] + d[c] * _dot(_sub(hd, sh), d) * (arm - 1) for c in range(3)]   # запястье после удлинения руки
        for i, v in enumerate(vs):
            if v[0] * sx <= 0:
                continue
            a, f = jw.get(i, (aw.get(i, 0.0), fw.get(i, 0.0)))
            if a > 0:
                t = _dot(_sub(v, sh), d)
                if t > 0:
                    for c in range(3):
                        v[c] += d[c] * t * (arm - 1) * a
            h = jh.get(i, hw.get(i, 0.0))
            if h > 0:                                  # кисть крупнее (Meshy-лист): от запястья ×hand
                for c in range(3):
                    v[c] = hd2[c] + (v[c] - hd2[c]) * (1 + (hand - 1) * h)
            if f > 0:
                dz = v[2] - an[2]
                v[2] = an[2] + dz * (1 + (foot - 1) * f)
                dx = v[0] - an[0]
                v[0] = an[0] + dx * (1 + 0.2 * f)          # стопа шире (у Meshy-листа стопа крупнее)


def leg_weights(sk):
    """Доля «ноги» каждой вершины по весам скелета (для пропорций: ноги и торс масштабируются по-разному)."""
    out = {}
    for i, ws in sk.weights.items():
        tot = sum(w for _, w in ws) or 1.0
        out[i] = sum(w for b, w in ws if b.startswith(LEG_BONES)) / tot
    return out


def to_character(vs, faces, groups, neck_z, pelvis_z, s=1.0, slim=1.0, cut_y=None, legw=None):
    """Перевод в координаты игры (Z вверх, лицо −Y, метры) с пропорциями персонажа.
    Ниже таза — масштаб, ставящий таз на pelvis_z (ноги); выше — масштаб от таза до шеи (neck_z).
    slim — сужение по X/Y. Вершины головы (выше cut_y, по высоте MakeHuman) убираются.
    Возвращает (verts, faces, J) — J: суставы MakeHuman в тех же координатах."""
    ground = joint(vs, groups, "ground")[1]
    p_y = joint(vs, groups, "pelvis")[1]
    n_y = joint(vs, groups, "neck")[1]
    k_leg = pelvis_z / (p_y - ground)
    k_up = (neck_z - pelvis_z) / (n_y - p_y)
    k_xy = k_up * slim

    def conv(v, lw):
        # Ноги — масштаб ног (тоньше), торс и руки — масштаб торса; доля lw — по весам скелета,
        # а не по высоте (иначе опущенные ниже таза кисти ломаются на линии таза).
        z = (1 - lw) * (pelvis_z + (v[1] - p_y) * k_up) + lw * ((v[1] - ground) * k_leg)
        kx = (1 - lw) * k_xy + lw * k_leg * 0.96      # ноги по ширине (колени, икры)…
        ky = (1 - lw) * k_up + lw * k_leg * 1.0       # …глубина торса без сужения (грудная клетка объёмнее)
        return (v[0] * kx, -v[2] * ky, z)

    def lw_of(i):
        if legw is not None and i in legw:
            return legw[i]
        return 1.0 if vs[i][1] < p_y else 0.0
    if cut_y is None:
        cut_y = joint(vs, groups, "neck")[1] + 0.3 * (joint(vs, groups, "jaw")[1] - joint(vs, groups, "neck")[1])
    keep = {i for f in faces for i in f}
    keep = {i for i in keep if vs[i][1] <= cut_y}
    remap, out_v = {}, []
    for i in sorted(keep):
        remap[i] = len(out_v)
        out_v.append(conv(vs[i], lw_of(i)))
    out_f = [[remap[i] for i in f] for f in faces if all(i in remap for i in f)]
    J = {}
    for name in groups:
        if name.startswith("joint-"):
            n = name[6:]
            lw = 1.0 if any(t in n for t in ("upper-leg", "knee", "ankle", "foot", "toe", "ground")) else 0.0
            J[n] = conv(joint(vs, groups, n), lw)
    return out_v, out_f, J
