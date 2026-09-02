"""§splashIdentity — Génère l'icône de la fenêtre de lancement Android.

Pourquoi un script plutôt qu'un PNG posé à la main : l'icône doit exister en 5
densités, rester alignée sur l'identité visuelle (dégradé `kAetherGradient`
vert Matrix → cyan, glow) et pouvoir être RE-générée si la charte bouge. Le
paramétrage est ici, en haut du fichier.

    python tool/gen_splash_icon.py            # écrit les drawables Android
    python tool/gen_splash_icon.py --preview  # rend un aperçu sur fond #121212

⚠️ L'icône native ne peut PAS suivre le thème choisi par l'utilisateur : elle est
lue par Android avant tout code Dart. On fige donc l'identité PAR DÉFAUT (preset
Matrix), qui est aussi celle de l'écran de démarrage au premier lancement.
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFilter

# ── Charte ──────────────────────────────────────────────────────────────────
# Identiques à `kAccentPrimary` / `kAccentSecondary` du preset Matrix
# (lib/core/themes/colors.dart) — c'est `kAetherGradient`.
GREEN = (0x00, 0xFF, 0x41)
CYAN = (0x00, 0xCE, 0xD1)
BOOT_BG = (0x12, 0x12, 0x12)  # = @color/aether_boot_background

SS = 4  # supersampling : on dessine en grand, on réduit → antialiasing propre

# Densités Android, avec la taille finale en pixels (mdpi = 1×).
DENSITIES = {
    "mdpi": 118,
    "hdpi": 177,
    "xhdpi": 236,
    "xxhdpi": 354,
    "xxxhdpi": 473,
}

RES = "android/app/src/main/res"

# Points de contrôle de l'onde, en coordonnées relatives.
# x ∈ [0,1] sur la largeur utile ; y ∈ [-1,1], 0 = ligne médiane, + = vers le haut.
# Une ligne de base calme, un pic franc, un rebond : ça se lit en un coup d'œil,
# là où l'ancienne onde à cinq oscillations devenait illisible en petit.
WAVE = [
    (0.00, 0.00),
    (0.22, 0.00),
    (0.31, 0.16),
    (0.39, -0.10),
    (0.47, 0.90),
    (0.56, -0.72),
    (0.65, 0.22),
    (0.74, 0.00),
    (1.00, 0.00),
]


def catmull_rom(points, samples_per_seg=24):
    """Lisse une polyligne (Catmull-Rom) — sans ça l'onde serait anguleuse."""
    pts = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(len(pts) - 3):
        p0, p1, p2, p3 = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
        for s in range(samples_per_seg):
            t = s / samples_per_seg
            t2, t3 = t * t, t * t * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t +
                       (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 +
                       (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t +
                       (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 +
                       (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    out.append(points[-1])
    return out


def gradient_image(size):
    """Dégradé diagonal vert Matrix → cyan : `kAetherGradient`, en pixels."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = (
                int(GREEN[0] + (CYAN[0] - GREEN[0]) * t),
                int(GREEN[1] + (CYAN[1] - GREEN[1]) * t),
                int(GREEN[2] + (CYAN[2] - GREEN[2]) * t),
            )
    return img


def build_mask(size):
    """Silhouette du signe : anneau + onde + deux points d'accent."""
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    c = size / 2

    # Anneau FERMÉ. Une première version l'ouvrait en haut : combiné aux deux
    # points d'accent, ça donnait un visage souriant. Supprimés tous les deux.
    r = size * 0.435
    ring_w = max(1, int(size * 0.036))
    d.ellipse([c - r, c - r, c + r, c + r], outline=255, width=ring_w)

    # Onde : large et ample, trait FIN. La version précédente avait un trait
    # épais sur une petite amplitude → les oscillations fusionnaient en pâté.
    span = size * 0.60
    amp = size * 0.255
    x0 = c - span / 2
    pts = [(x0 + x * span, c - y * amp) for x, y in catmull_rom(WAVE)]
    d.line(pts, fill=255, width=max(1, int(size * 0.038)), joint="curve")

    # Terminaisons rondes (ImageDraw.line n'en pose pas).
    cap = size * 0.019
    for (x, y) in (pts[0], pts[-1]):
        d.ellipse([x - cap, y - cap, x + cap, y + cap], fill=255)
    return m


def render(final_size, scale=1.0):
    """Rend l'icône (RGBA, fond transparent) à la taille demandée.

    [scale] < 1 réduit le SIGNE en laissant une marge transparente autour.
    Indispensable pour Android 12+ : le système inscrit l'icône dans un masque
    CIRCULAIRE et n'en garde que les deux tiers centraux — un anneau dessiné
    bord à bord y serait rogné net.
    """
    if scale != 1.0:
        inner = max(1, int(final_size * scale))
        art = render(inner)
        canvas = Image.new("RGBA", (final_size, final_size), (0, 0, 0, 0))
        off = (final_size - inner) // 2
        canvas.alpha_composite(art, (off, off))
        return canvas

    s = final_size * SS
    mask = build_mask(s)
    grad = gradient_image(s)

    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    # Glow : deux passes floues, du plus large au plus serré. C'est le halo
    # néon de l'app — l'ancienne icône était un aplat sans profondeur.
    for blur, alpha in ((s * 0.045, 62), (s * 0.016, 105)):
        halo = mask.filter(ImageFilter.GaussianBlur(blur))
        halo = halo.point(lambda v: int(v * alpha / 255))
        layer = Image.new("RGBA", (s, s), GREEN + (0,))
        layer.putalpha(halo)
        out = Image.alpha_composite(out, layer)

    core = grad.convert("RGBA")
    core.putalpha(mask)
    out = Image.alpha_composite(out, core)

    return out.resize((final_size, final_size), Image.LANCZOS)


# Android 12+ ne garde que les 2/3 centraux de l'icône (masque circulaire).
ANDROID12_SCALE = 0.66

def write_drawables():
    written = 0
    for density, px in DENSITIES.items():
        variants = {
            "splash.png": render(px),                        # Android ≤ 11
            "android12splash.png": render(px, ANDROID12_SCALE),
        }
        for folder in ("drawable-%s" % density, "drawable-night-%s" % density):
            path = os.path.join(RES, folder)
            if not os.path.isdir(path):
                continue
            for name, icon in variants.items():
                target = os.path.join(path, name)
                # On ne CRÉE pas de nouveaux fichiers : on remplace ceux que le
                # manifeste référence déjà.
                if os.path.exists(target):
                    icon.save(target)
                    written += 1
    print("%d fichiers écrits." % written)


def write_preview():
    """Aperçu côte à côte : Android ≤ 11 (plein cadre) et 12+ (masqué en cercle).

    Le cercle tracé sur la 2e vignette matérialise la découpe du système : ce
    qui déborde est perdu.
    """
    size = 300
    pad = 60
    canvas = Image.new("RGBA", (size * 2 + pad * 3, size + pad * 2), BOOT_BG + (255,))
    canvas.alpha_composite(render(size), (pad, pad))
    canvas.alpha_composite(render(size, ANDROID12_SCALE), (pad * 2 + size, pad))
    d = ImageDraw.Draw(canvas)
    cx, cy = pad * 2 + size + size / 2, pad + size / 2
    r = size / 2
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(90, 90, 90, 255), width=2)
    out = "tool/_splash_preview.png"
    canvas.convert("RGB").save(out)
    print("Aperçu :", out)

# ── §tvBanner ───────────────────────────────────────────────────────────────
# Le lanceur Android TV (Leanback) n'affiche PAS l'icône : il affiche une tuile
# paysage 320×180 dp, où toutes les applications montrent leur NOM. La nôtre
# montrait `@mipmap/launcher_icon` — une carte promotionnelle contenant le nom,
# un slogan ET le logo Flutter — rétrécie à 120 dp au milieu d'un rectangle noir.
# Illisible à côté de Live TV ou Play Store, et en palette cyan/magenta,
# c'est-à-dire l'ancienne identité, celle que l'écran Matrix a remplacée.
BANNER_BASE = (320, 180)
# §apkDiet (2026-09-02) — UNE seule densité, xhdpi (640×360).
#
# Android TV dessine son interface à 1080p et la met à l'échelle sur les dalles
# 4K : les box et téléviseurs se déclarent donc en xhdpi (~320 dpi), jamais en
# mdpi ni en xxhdpi. Les trois autres densités n'étaient servies à personne et
# pesaient 238 Ko à elles seules (la xxhdpi seule : 146 Ko).
#
# ⚠️ Ne pas « rétablir par sécurité » : ré-ajouter une clé ici remet aussi les
# fichiers dans le dépôt à la prochaine exécution du script.
BANNER_DENSITIES = {"xhdpi": 2.0}

# ⚠️ Aucune police n'est versionnée dans le dépôt (l'app charge les siennes à
# l'exécution via `google_fonts`). On cherche donc une graisse lourde parmi les
# polices système, du plus proche de la charte au plus banal. Si rien n'est
# trouvé, on écrit quand même la tuile — sans texte plutôt que pas de tuile.
FONT_CANDIDATES = [
    "C:/Windows/Fonts/seguibl.ttf",   # Segoe UI Black
    "C:/Windows/Fonts/arialbd.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def _font(px):
    from PIL import ImageFont
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, px)
            except Exception:
                continue
    return None


def render_banner(width, height):
    """Tuile Leanback : le signe à gauche, le nom à droite, sur le fond du boot.

    ⚠️ Le nom est ÉCRIT dans la tuile, pas seulement dans le manifeste : le
    lanceur n'affiche le libellé sous la vignette que pour les favoris. Dans la
    grille « Applications », la tuile est seule à identifier l'app.
    """
    ss = 3
    w, h = int(width) * ss, int(height) * ss
    img = Image.new("RGBA", (w, h), BOOT_BG + (255,))
    d = ImageDraw.Draw(img)

    # ⚠️ **Retour utilisateur : « ça fait un peu vide ».** Un signe centré sur un
    # aplat noir tient sur une icône carrée, pas sur une tuile 16/9 : à côté des
    # vignettes pleines du lanceur, la nôtre ressemblait à un trou. On remplit
    # donc le cadre avec le MOTIF de l'identité — l'onde, en grand, traversant
    # toute la largeur — plutôt qu'avec un décor étranger.
    #
    # L'onde de fond est tracée à ~12 % d'opacité et floutée : elle donne de la
    # matière sans jamais concurrencer le nom, qui reste l'information utile.
    field = Image.new("L", (w, h), 0)
    fd = ImageDraw.Draw(field)
    # ⚠️ `stroke` et pas `width` : ce nom est déjà celui du PARAMÈTRE de la
    # fonction. Le réutiliser ici l'écrasait, et le redimensionnement final
    # recevait 0,02 au lieu de 320 — erreur PIL parfaitement opaque.
    for i, (amp, alpha, stroke) in enumerate(
            ((0.46, 132, 0.030), (0.30, 96, 0.020), (0.17, 70, 0.014),
             (0.09, 52, 0.010))):
        pts = [(x * w, h * 0.5 - y * h * amp) for x, y in catmull_rom(WAVE)]
        # Décalage vertical léger par passe → impression de nappe, pas de copie.
        pts = [(x, y + (i - 1) * h * 0.05) for x, y in pts]
        layer = Image.new("L", (w, h), 0)
        ImageDraw.Draw(layer).line(pts, fill=alpha, width=max(1, int(h * stroke)),
                                   joint="curve")
        field = Image.eval(Image.blend(field, layer, 0.5), lambda v: min(255, v * 2))
    field = field.filter(ImageFilter.GaussianBlur(int(h * 0.006) or 1))
    grad_bg = gradient_image(int(max(w, h))).resize((int(w), int(h)))
    bg = grad_bg.convert("RGBA")
    bg.putalpha(field)
    img = Image.alpha_composite(img, bg)

    # ⚠️ Plus la nappe est dense, plus il faut protéger le NOM : c'est lui
    # l'information utile, la matière n'est qu'un décor. Deux voiles distincts —
    # un dégradé à gauche pour détacher le signe, et un halo doux SOUS le texte,
    # flouté pour ne pas se voir comme une tache.
    veil = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    vd = ImageDraw.Draw(veil)
    for x in range(w):
        a = int(120 * max(0.0, 1.0 - x / (w * 0.55)))
        vd.line([(x, 0), (x, h)], fill=(0, 0, 0, a))
    img = Image.alpha_composite(img, veil)

    halo = Image.new("L", (w, h), 0)
    ImageDraw.Draw(halo).ellipse(
        [int(w * 0.50), int(h * 0.18), int(w * 1.02), int(h * 0.82)], fill=190)
    halo = halo.filter(ImageFilter.GaussianBlur(int(h * 0.10) or 1))
    shade = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    shade.putalpha(halo)
    img = Image.alpha_composite(img, shade)
    d = ImageDraw.Draw(img)

    # Filet dégradé en pied de tuile — même signature que l'écran de démarrage.
    for x in range(w):
        t = x / max(1, w - 1)
        c = tuple(int(GREEN[i] + (CYAN[i] - GREEN[i]) * t) for i in range(3))
        d.line([(x, h - 3 * ss), (x, h)], fill=c + (255,))

    mark = int(h * 0.72)
    img.alpha_composite(render(mark), (int(h * 0.16), (h - mark) // 2))

    # ⚠️ La taille du texte se DÉDUIT de la place restante, elle ne se devine
    # pas : un ratio fixe de la hauteur donnait « Aethe » — le mot sortait de
    # la tuile. On part grand et on réduit jusqu'à ce que ça rentre.
    tx = int(h * 0.16) + mark + int(h * 0.12)
    avail = w - tx - int(h * 0.12)
    name = "AetherStream"
    f, tw, th = None, 0, 0
    for px in range(int(h * 0.30), 8, -1):
        cand = _font(px)
        if cand is None:
            break
        box = d.textbbox((0, 0), name, font=cand)
        if box[2] - box[0] <= avail:
            f, tw, th = cand, box[2] - box[0], box[3] - box[1]
            break
    if f is not None:
        ty = (h - th) // 2 - int(h * 0.04)
        # Ombre portée : la tuile est survolée sur un fond qui s'éclaircit.
        d.text((tx + ss, ty + ss), name, font=f, fill=(0, 0, 0, 160))
        d.text((tx, ty), name, font=f, fill=(255, 255, 255, 255))

    return img.resize((int(width), int(height)), Image.LANCZOS)


def write_banner():
    written = []
    for density, factor in BANNER_DENSITIES.items():
        folder = os.path.join(RES, "drawable-%s" % density)
        if not os.path.isdir(folder):
            os.makedirs(folder, exist_ok=True)
        size = (int(BANNER_BASE[0] * factor), int(BANNER_BASE[1] * factor))
        target = os.path.join(folder, "banner_tv.png")
        render_banner(*size).convert("RGB").save(target)
        written.append("%s (%dx%d)" % (target, *size))
    # ⚠️ L'ancien `drawable/banner_tv.xml` doit disparaître : un `layer-list` et
    # un PNG de MÊME nom sont deux ressources concurrentes, et c'est le xml qui
    # gagne sur les densités non couvertes.
    old = os.path.join(RES, "drawable", "banner_tv.xml")
    if os.path.exists(old):
        os.remove(old)
        written.append("%s (supprimé)" % old)
    print(chr(10).join(written))

if __name__ == "__main__":
    if "--banner" in sys.argv:
        write_banner()
    elif "--preview" in sys.argv:
        write_preview()
    else:
        write_drawables()
