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


if __name__ == "__main__":
    if "--preview" in sys.argv:
        write_preview()
    else:
        write_drawables()
