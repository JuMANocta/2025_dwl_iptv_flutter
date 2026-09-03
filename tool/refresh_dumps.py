#!/usr/bin/env python3
"""Rafraîchit les catalogues réels de `lib/iptv_exemple/`.

**Pourquoi cet outil existe.** Le parsing des titres se corrige en le mesurant
sur les vrais catalogues — c'est la méthode du projet (§xenoFormat : « films
XENO ∩ PLATINIUM 165 → 13 191 »). Mais les dumps se périment : ceux du
2026-06-10 ne contenaient plus les formes signalées en août (`[VQF/]`,
`[ SUB-AR]`, `WHIPLASH (2014)(MULTi)`). On ne peut pas corriger ce qu'on ne peut
pas reproduire.

Les identifiants ne sont pas dans le dépôt : ils viennent de la **sauvegarde
`.aether`** de l'application (AES-256-GCM + PBKDF2-SHA256, format documenté dans
`lib/data/services/backup_service.dart`). Ce script la déchiffre, appelle
`player_api.php` pour chaque compte et réécrit les dumps.

    python tool/refresh_dumps.py                 # tous les comptes
    python tool/refresh_dumps.py --only VOD      # un seul
    python tool/refresh_dumps.py --password PW   # sinon lu dans le skill

⚠️ **N'imprime jamais un identifiant.** Les URLs sont journalisées masquées.
⚠️ N'écrit que dans `lib/iptv_exemple/`, qui est gitignoré.
"""
import argparse
import gzip
import hashlib
import io
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

# ⚠️ La console Windows est en cp1252 : sans ça, la première flèche « → »
# fait tomber le script APRÈS avoir écrit le dump (diagnostic trompeur).
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DUMPS = os.path.join(ROOT, "lib", "iptv_exemple")
BACKUP = os.path.join(DUMPS, "accounts.aether")
PW_FILE = os.path.join(ROOT, ".claude", "skills", "run-aetherstream",
                       "backup_password.txt")

# §iptvUaCompat — les panels Xtream répondent 500 EN SILENCE aux UA navigateur.
# Ce profil est celui de `NetworkUtils.buildBaseDio` ; ne pas y ajouter de
# Referer ni d'Origin.
HEADERS = {
    "User-Agent": "IPTVSmartersPro",
    "Accept": "*/*",
    "Accept-Encoding": "gzip",
}

# Les trois listes que contiennent les dumps existants, dans le même ordre.
ACTIONS = [("live", "get_live_streams"),
           ("vod", "get_vod_streams"),
           ("series", "get_series")]


def redact(url):
    """Masque identifiants et hôte — un log ne doit jamais fuiter un compte."""
    u = urllib.parse.urlsplit(url)
    q = urllib.parse.parse_qs(u.query)
    action = q.get("action", ["?"])[0]
    return "%s://***/player_api.php?action=%s" % (u.scheme, action)


def decrypt_backup(path, password):
    """Lit un `.aether`. Format : AETH | ver | salt16 | nonce12 | ct | mac16."""
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    raw = open(path, "rb").read()
    if raw[:4] != b"AETH":
        raise SystemExit("%s n'est pas une sauvegarde AetherStream." % path)
    if raw[4] != 1:
        raise SystemExit("Version de format inconnue : %d." % raw[4])
    salt, nonce, body = raw[5:21], raw[21:33], raw[33:]
    key = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt,
                              100000, 32)
    try:
        clear = AESGCM(key).decrypt(nonce, body, None)
    except Exception:
        raise SystemExit("Mot de passe incorrect (le MAC GCM ne valide pas).")
    return json.loads(clear.decode("utf-8"))


def credentials(account):
    """(base, user, pass) — quel que soit le mode d'enregistrement du compte.

    ⚠️ Un compte en mode « URL complète » n'a pas forcément `username` /
    `password` renseignés : ils vivent alors dans la query de `get.php`. On
    couvre les deux, sinon les comptes historiques sont muets.
    """
    base = (account.get("baseUrl") or "").rstrip("/")
    user = account.get("username") or ""
    pwd = account.get("password") or ""
    full = account.get("completeUrl") or ""
    if full and (not base or not user or not pwd):
        u = urllib.parse.urlsplit(full)
        q = urllib.parse.parse_qs(u.query)
        base = base or "%s://%s" % (u.scheme, u.netloc)
        user = user or (q.get("username") or [""])[0]
        pwd = pwd or (q.get("password") or [""])[0]
    return base, user, pwd


def fetch(url, timeout=180):
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = resp.read()
        if resp.headers.get("Content-Encoding") == "gzip":
            data = gzip.decompress(data)
    return json.loads(data.decode("utf-8", "replace"))


def slug(label):
    return re.sub(r"[^A-Za-z0-9]+", "", label).upper() or "COMPTE"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--password", help="sinon lu dans le skill (gitignoré)")
    ap.add_argument("--backup", default=BACKUP)
    ap.add_argument("--only", help="ne traiter que ce libellé de compte")
    args = ap.parse_args()

    pw = args.password
    if not pw and os.path.exists(PW_FILE):
        pw = open(PW_FILE, encoding="utf-8").read().strip()
    if not pw:
        raise SystemExit(
            "Mot de passe absent : --password, ou le déposer dans\n  %s" % PW_FILE)

    data = decrypt_backup(args.backup, pw)
    accounts = data.get("accounts", [])
    print("Sauvegarde du %s — %d compte(s)."
          % (data.get("exportedAt", "?")[:10], len(accounts)))

    for acc in accounts:
        label = acc.get("label") or "?"
        if args.only and args.only.lower() != label.lower():
            continue
        base, user, pwd = credentials(acc)
        if not (base and user and pwd):
            print("  %-12s IGNORÉ (pas d'identifiants Xtream exploitables)"
                  % label)
            continue
        out = {}
        ok = True
        for key, action in ACTIONS:
            url = ("%s/player_api.php?username=%s&password=%s&action=%s"
                   % (base, urllib.parse.quote(user),
                      urllib.parse.quote(pwd), action))
            t0 = time.time()
            try:
                payload = fetch(url)
            except Exception as exc:
                print("  %-12s %-8s ÉCHEC %s (%s)"
                      % (label, key, type(exc).__name__, redact(url)))
                out[key] = []
                ok = False
                continue
            if not isinstance(payload, list):
                # Un panel qui refuse répond souvent un objet d'erreur, pas 4xx.
                print("  %-12s %-8s réponse inattendue (%s)"
                      % (label, key, type(payload).__name__))
                payload = []
                ok = False
            out[key] = payload
            print("  %-12s %-8s %7d éléments  %5.1fs"
                  % (label, key, len(payload), time.time() - t0))
        dest = os.path.join(DUMPS, "%s_vod_cache.json" % slug(label))
        with io.open(dest, "w", encoding="utf-8") as fh:
            json.dump(out, fh, ensure_ascii=False, indent=4)
        print("  %-12s → %s (%.1f Mo)%s"
              % (label, os.path.basename(dest),
                 os.path.getsize(dest) / 1e6,
                 "" if ok else "  ⚠️ incomplet"))

    print("\nContrôle : dart run tool/validate_parse.dart")


if __name__ == "__main__":
    main()
