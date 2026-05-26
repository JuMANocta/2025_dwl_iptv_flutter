// Templates HTML inline servis par le PairingService (§3c-8).
//
// Le but : afficher une page de saisie sur le mobile qui reprend exactement
// l'identité visuelle du thème courant de l'app (Matrix, Blade Runner, Tron…).
// Les couleurs sont injectées via CSS variables interpolées à partir de
// `AppThemeConfig`. Polices Google Fonts (VT323 + Source Code Pro) pour
// matcher le côté cyberpunk terminal.

import 'package:flutter/material.dart';

import '../../core/themes/app_theme_config.dart';

/// Convertit une [Color] Flutter en `#RRGGBB`.
String _hex(Color c) {
  // ignore: deprecated_member_use
  final v = c.value & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Convertit une [Color] Flutter en triplet CSS `R, G, B` (pour rgba).
String _rgbCsv(Color c) {
  // ignore: deprecated_member_use
  final v = c.value;
  return '${(v >> 16) & 0xFF}, ${(v >> 8) & 0xFF}, ${v & 0xFF}';
}

/// Génère le bloc `:root { --... }` CSS depuis [theme].
String _cssVars(AppThemeConfig theme) {
  final primary = _hex(theme.primaryColor);
  final accent = _hex(theme.accentColor);
  final tertiary = _hex(theme.tertiaryColor);
  final glowBlur = (20 * theme.glowIntensity).round().clamp(0, 40);
  final glowAlpha = (0.45 * theme.glowIntensity).clamp(0.0, 0.8);
  final primaryRgb = _rgbCsv(theme.primaryColor);
  return '''
    :root {
      --primary: $primary;
      --accent: $accent;
      --tertiary: $tertiary;
      --bg: #050505;
      --surface: #121212;
      --surface-2: #1c1c1c;
      --text: #FFFFFF;
      --text-dim: #9A9A9A;
      --radius: ${theme.borderRadius}px;
      --glow: 0 0 ${glowBlur}px rgba($primaryRgb, $glowAlpha);
    }
  ''';
}

/// CSS commun aux 3 pages (form / success / error).
String _commonCss(AppThemeConfig theme) => '''
  ${_cssVars(theme)}

  * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }

  html, body {
    margin: 0;
    padding: 0;
    background: var(--bg);
    color: var(--text);
    font-family: 'Source Code Pro', ui-monospace, monospace;
    min-height: 100vh;
    -webkit-font-smoothing: antialiased;
  }

  body {
    background:
      radial-gradient(ellipse at top, rgba(255,255,255,0.02) 0%, transparent 60%),
      var(--bg);
    padding: 20px 16px 40px;
  }

  .container {
    max-width: 480px;
    margin: 0 auto;
  }

  .header {
    text-align: center;
    margin-bottom: 24px;
  }

  .header .logo {
    font-family: 'VT323', monospace;
    font-size: 42px;
    color: var(--primary);
    letter-spacing: 4px;
    text-shadow: var(--glow);
    line-height: 1;
  }

  .header .subtitle {
    color: var(--text-dim);
    font-size: 11px;
    letter-spacing: 2px;
    text-transform: uppercase;
    margin-top: 4px;
  }

  .card {
    background: var(--surface);
    border: 1px solid rgba(255,255,255,0.06);
    border-radius: var(--radius);
    padding: 24px 20px;
    box-shadow: var(--glow);
  }

  .field {
    margin-bottom: 16px;
  }

  .field label {
    display: block;
    font-size: 10px;
    letter-spacing: 1.5px;
    text-transform: uppercase;
    color: var(--text-dim);
    margin-bottom: 6px;
    font-weight: 700;
  }

  .field input,
  .field textarea {
    width: 100%;
    background: var(--surface-2);
    border: 1px solid rgba(255,255,255,0.08);
    border-radius: calc(var(--radius) - 2px);
    padding: 14px 14px;
    color: var(--text);
    font-family: inherit;
    font-size: 15px;
    transition: border-color .15s, box-shadow .15s;
  }

  .field input:focus,
  .field textarea:focus {
    outline: none;
    border-color: var(--primary);
    box-shadow: 0 0 0 3px rgba(255,255,255,0.04), var(--glow);
  }

  .field textarea {
    resize: vertical;
    min-height: 120px;
    font-size: 12px;
    word-break: break-all;
  }

  .field .hint {
    font-size: 11px;
    color: var(--text-dim);
    margin-top: 4px;
  }

  .mode-switch {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
    background: var(--surface-2);
    padding: 4px;
    border-radius: var(--radius);
    margin-bottom: 18px;
  }

  .mode-switch button {
    background: transparent;
    border: none;
    padding: 10px 8px;
    color: var(--text-dim);
    font-family: inherit;
    font-size: 12px;
    letter-spacing: 1px;
    text-transform: uppercase;
    font-weight: 700;
    cursor: pointer;
    border-radius: calc(var(--radius) - 4px);
    transition: background .15s, color .15s;
  }

  .mode-switch button.active {
    background: var(--primary);
    color: #000;
    box-shadow: var(--glow);
  }

  .submit {
    display: block;
    width: 100%;
    background: var(--primary);
    color: #000;
    border: none;
    border-radius: var(--radius);
    padding: 16px;
    font-family: inherit;
    font-size: 14px;
    font-weight: 800;
    letter-spacing: 2px;
    text-transform: uppercase;
    cursor: pointer;
    box-shadow: var(--glow);
    transition: transform .1s;
  }

  .submit:active { transform: translateY(1px); }
  .submit:disabled {
    opacity: .6;
    cursor: not-allowed;
  }

  .error-box {
    background: rgba(255,0,0,0.08);
    border: 1px solid rgba(255,0,0,0.4);
    color: #ff6b6b;
    padding: 10px 12px;
    border-radius: calc(var(--radius) - 2px);
    margin-bottom: 14px;
    font-size: 12px;
    display: none;
  }
  .error-box.show { display: block; }

  .footer-note {
    text-align: center;
    color: var(--text-dim);
    font-size: 11px;
    margin-top: 24px;
    line-height: 1.6;
  }

  .pwd-wrap { position: relative; }
  .pwd-toggle {
    position: absolute;
    top: 50%;
    right: 8px;
    transform: translateY(-50%);
    background: transparent;
    border: none;
    color: var(--text-dim);
    cursor: pointer;
    padding: 4px 8px;
    font-family: inherit;
    font-size: 10px;
    letter-spacing: 1px;
  }
  .pwd-toggle:hover { color: var(--primary); }

  .divider {
    height: 1px;
    background: rgba(255,255,255,0.08);
    margin: 22px 0 18px;
  }

  .success-icon {
    width: 96px;
    height: 96px;
    margin: 0 auto 20px;
    border-radius: 50%;
    background: radial-gradient(circle, rgba(255,255,255,0.06) 0%, transparent 70%);
    border: 2px solid var(--primary);
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: var(--glow);
    animation: pulse 2s ease-in-out infinite;
  }
  .success-icon::after {
    content: "✓";
    color: var(--primary);
    font-size: 56px;
    font-weight: 700;
    line-height: 1;
    text-shadow: var(--glow);
  }
  @keyframes pulse {
    0%, 100% { transform: scale(1); }
    50% { transform: scale(1.04); }
  }

  .success-title {
    text-align: center;
    font-family: 'VT323', monospace;
    font-size: 32px;
    color: var(--primary);
    letter-spacing: 3px;
    margin: 0 0 12px;
    text-shadow: var(--glow);
  }
  .success-body {
    text-align: center;
    color: var(--text-dim);
    font-size: 14px;
    line-height: 1.6;
    margin: 0;
  }
''';

const String _googleFontsLink = '''
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=VT323&family=Source+Code+Pro:wght@400;600;800&display=swap" rel="stylesheet">
''';

/// Form de pairing pour un compte IPTV (mode URL complète OU Xtream Codes).
String buildAccountForm({required AppThemeConfig theme, required String token}) {
  return '''
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
  <meta name="color-scheme" content="dark">
  <title>AetherStream · Pairing</title>
  $_googleFontsLink
  <style>${_commonCss(theme)}</style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="logo">AETHERSTREAM</div>
      <div class="subtitle">Configuration depuis mobile</div>
    </div>

    <div class="card">
      <div class="mode-switch">
        <button type="button" id="modeUrl" class="active" onclick="setMode('complete')">URL complète</button>
        <button type="button" id="modeXtream" onclick="setMode('separate')">Xtream Codes</button>
      </div>

      <div class="error-box" id="errBox"></div>

      <div class="field">
        <label for="label">Nom du compte (optionnel)</label>
        <input type="text" id="label" autocomplete="off" placeholder="Mon abonnement">
      </div>

      <div id="urlFields">
        <div class="field">
          <label for="url">URL M3U complète</label>
          <input type="url" id="url" autocomplete="off" placeholder="http://serveur/get.php?username=...">
          <div class="hint">URL .m3u ou .m3u8 fournie par ton provider.</div>
        </div>
      </div>

      <div id="xtreamFields" style="display:none">
        <div class="field">
          <label for="base">URL serveur</label>
          <input type="url" id="base" autocomplete="off" placeholder="http://serveur.tv:8080">
        </div>
        <div class="field">
          <label for="user">Nom d'utilisateur</label>
          <input type="text" id="user" autocomplete="off">
        </div>
        <div class="field">
          <label for="pass">Mot de passe</label>
          <div class="pwd-wrap">
            <input type="password" id="pass" autocomplete="off">
            <button type="button" class="pwd-toggle" id="pwdToggle" onclick="togglePwd()">AFFICHER</button>
          </div>
        </div>
      </div>

      <div class="divider"></div>

      <div class="field">
        <label for="tmdb">Clé TMDB <span style="opacity: .5; font-weight: 400; text-transform: none; letter-spacing: 0;">(optionnel)</span></label>
        <textarea id="tmdb" autocomplete="off" placeholder="eyJhbGciOiJIUzI1NiJ9…"></textarea>
        <div class="hint">
          Optionnel — pour les affiches et synopsis. Récupère ton token sur
          <a href="https://www.themoviedb.org/settings/api" target="_blank" style="color: var(--accent);">themoviedb.org/settings/api</a>.
          Tu pourras aussi l'ajouter plus tard depuis la TV.
        </div>
      </div>

      <button type="button" class="submit" id="submitBtn" onclick="submitForm()">Envoyer à la TV</button>
    </div>

    <p class="footer-note">
      Cette page est servie par ta TV.<br>
      Les identifiants restent sur ton réseau local.
    </p>
  </div>

  <script>
    let mode = 'complete';
    function setMode(m) {
      mode = m;
      document.getElementById('modeUrl').classList.toggle('active', m === 'complete');
      document.getElementById('modeXtream').classList.toggle('active', m === 'separate');
      document.getElementById('urlFields').style.display = m === 'complete' ? '' : 'none';
      document.getElementById('xtreamFields').style.display = m === 'separate' ? '' : 'none';
      hideError();
    }
    function togglePwd() {
      const inp = document.getElementById('pass');
      const btn = document.getElementById('pwdToggle');
      if (inp.type === 'password') { inp.type = 'text'; btn.textContent = 'MASQUER'; }
      else { inp.type = 'password'; btn.textContent = 'AFFICHER'; }
    }
    function showError(msg) {
      const box = document.getElementById('errBox');
      box.textContent = msg;
      box.classList.add('show');
    }
    function hideError() {
      document.getElementById('errBox').classList.remove('show');
    }
    async function submitForm() {
      hideError();
      const btn = document.getElementById('submitBtn');
      const tmdbVal = (document.getElementById('tmdb').value || '').trim();
      const payload = {
        mode,
        label: document.getElementById('label').value,
        tmdb: tmdbVal,
      };
      if (mode === 'complete') {
        payload.url = document.getElementById('url').value;
        if (!payload.url || !payload.url.trim()) return showError('URL requise.');
      } else {
        payload.base = document.getElementById('base').value;
        payload.user = document.getElementById('user').value;
        payload.pass = document.getElementById('pass').value;
        if (!payload.base.trim() || !payload.user.trim() || !payload.pass.trim()) {
          return showError('Tous les champs sont requis.');
        }
      }
      if (tmdbVal && tmdbVal.length < 20) {
        return showError('Clé TMDB trop courte — vérifie le copier-coller (ou vide pour ignorer).');
      }
      btn.disabled = true;
      btn.textContent = 'Envoi en cours…';
      try {
        const res = await fetch('/submit?t=$token', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });
        if (res.ok) {
          document.documentElement.innerHTML = await res.text();
        } else {
          const j = await res.json().catch(() => ({ error: 'Erreur serveur.' }));
          showError(j.error || 'Erreur serveur.');
          btn.disabled = false;
          btn.textContent = 'Envoyer à la TV';
        }
      } catch (e) {
        showError('Connexion perdue avec la TV.');
        btn.disabled = false;
        btn.textContent = 'Envoyer à la TV';
      }
    }
  </script>
</body>
</html>
''';
}

/// Form de pairing pour le Bearer Token TMDB.
String buildTmdbForm({required AppThemeConfig theme, required String token}) {
  return '''
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
  <meta name="color-scheme" content="dark">
  <title>AetherStream · TMDB</title>
  $_googleFontsLink
  <style>${_commonCss(theme)}</style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="logo">AETHERSTREAM</div>
      <div class="subtitle">Clé API TMDB</div>
    </div>

    <div class="card">
      <div class="error-box" id="errBox"></div>

      <div class="field">
        <label for="token">Bearer Token v4</label>
        <textarea id="token" autocomplete="off" placeholder="eyJhbGciOiJIUzI1NiJ9…"></textarea>
        <div class="hint">
          1. Ouvre <a href="https://www.themoviedb.org/settings/api" target="_blank" style="color: var(--accent);">themoviedb.org/settings/api</a><br>
          2. Copie le <strong>Read Access Token v4</strong><br>
          3. Colle-le ici puis envoie.
        </div>
      </div>

      <button type="button" class="submit" id="submitBtn" onclick="submitForm()">Envoyer à la TV</button>
    </div>

    <p class="footer-note">
      Cette page est servie par ta TV.<br>
      Le token reste sur ton réseau local.
    </p>
  </div>

  <script>
    function showError(msg) {
      const box = document.getElementById('errBox');
      box.textContent = msg;
      box.classList.add('show');
    }
    function hideError() {
      document.getElementById('errBox').classList.remove('show');
    }
    async function submitForm() {
      hideError();
      const btn = document.getElementById('submitBtn');
      const t = document.getElementById('token').value.trim();
      if (!t) return showError('Token requis.');
      if (t.length < 20) return showError('Token trop court — vérifie ton copier-coller.');
      btn.disabled = true;
      btn.textContent = 'Envoi en cours…';
      try {
        const res = await fetch('/submit?t=$token', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ token: t }),
        });
        if (res.ok) {
          document.documentElement.innerHTML = await res.text();
        } else {
          const j = await res.json().catch(() => ({ error: 'Erreur serveur.' }));
          showError(j.error || 'Erreur serveur.');
          btn.disabled = false;
          btn.textContent = 'Envoyer à la TV';
        }
      } catch (e) {
        showError('Connexion perdue avec la TV.');
        btn.disabled = false;
        btn.textContent = 'Envoyer à la TV';
      }
    }
  </script>
</body>
</html>
''';
}

/// §18 — String d'un [ThemeMode] pour le wire JSON ('system' / 'light' / 'dark').
String _modeStr(ThemeMode m) => switch (m) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };

/// §18 — Webapp Settings complète servie au mobile (thème + TMDB + EPG).
///
/// Élimine les focus-traps TV : color picker (`input type=color` natif OS),
/// sliders (`input type=range`), TextField clé TMDB. Sections repliables via
/// `<details>` natif. Mini-preview live du thème rendue en CSS.
///
/// [tmdbConfigured] : si `true`, le champ TMDB est laissé vide (placeholder
/// "déjà configurée") — l'envoyer vide = inchangé ; cocher "supprimer" = effacer.
String buildSettingsForm({
  required AppThemeConfig theme,
  required String token,
  required bool tmdbConfigured,
}) {
  final presetsJs = AppThemeConfig.presets.map((p) {
    final c = p.config;
    return "'${p.name}':{primary:'${_hex(c.primaryColor)}',accent:'${_hex(c.accentColor)}',"
        "tertiary:'${_hex(c.tertiaryColor)}',glow:${c.glowIntensity},"
        "radius:${c.borderRadius},mode:'${_modeStr(c.themeMode)}'}";
  }).join(',');

  final presetOptions = AppThemeConfig.presets
      .map((p) => '<option value="${p.name}">${p.name}</option>')
      .join();

  final curPrimary = _hex(theme.primaryColor);
  final curAccent = _hex(theme.accentColor);
  final curTertiary = _hex(theme.tertiaryColor);
  final curGlow = theme.glowIntensity;
  final curRadius = theme.borderRadius;
  final curMode = _modeStr(theme.themeMode);

  return '''
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
  <meta name="color-scheme" content="dark">
  <title>AetherStream · Paramètres</title>
  $_googleFontsLink
  <style>
    ${_commonCss(theme)}

    details {
      background: var(--surface);
      border: 1px solid rgba(255,255,255,0.06);
      border-radius: var(--radius);
      margin-bottom: 14px;
      overflow: hidden;
    }
    details[open] { box-shadow: var(--glow); }
    summary {
      list-style: none;
      cursor: pointer;
      padding: 16px 18px;
      font-size: 13px;
      letter-spacing: 1.5px;
      text-transform: uppercase;
      font-weight: 700;
      color: var(--primary);
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    summary::-webkit-details-marker { display: none; }
    summary::after { content: "▾"; color: var(--text-dim); transition: transform .2s; }
    details[open] summary::after { transform: rotate(180deg); }
    .section-body { padding: 4px 18px 20px; }

    .row { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 14px; }
    .row label { margin: 0; flex: 0 0 auto; }

    input[type=color] {
      -webkit-appearance: none; appearance: none;
      width: 52px; height: 34px;
      background: none; border: 1px solid rgba(255,255,255,0.12);
      border-radius: 8px; cursor: pointer; padding: 2px;
    }
    input[type=color]::-webkit-color-swatch-wrapper { padding: 0; }
    input[type=color]::-webkit-color-swatch { border: none; border-radius: 6px; }

    input[type=range] {
      -webkit-appearance: none; appearance: none;
      width: 60%; height: 4px; border-radius: 4px;
      background: var(--surface-2); outline: none;
    }
    input[type=range]::-webkit-slider-thumb {
      -webkit-appearance: none; appearance: none;
      width: 18px; height: 18px; border-radius: 50%;
      background: var(--primary); box-shadow: var(--glow); cursor: pointer;
    }

    select {
      width: 100%; background: var(--surface-2);
      border: 1px solid rgba(255,255,255,0.08);
      border-radius: calc(var(--radius) - 2px);
      padding: 12px 14px; color: var(--text);
      font-family: inherit; font-size: 14px;
    }

    .preview {
      margin: 4px 0 16px; padding: 16px;
      border-radius: var(--pv-radius, 8px);
      background: var(--surface-2);
      border: 1px solid rgba(255,255,255,0.06);
    }
    .preview .pv-title {
      font-family: 'VT323', monospace; font-size: 26px; letter-spacing: 2px;
      color: var(--pv-primary, var(--primary));
      text-shadow: 0 0 var(--pv-glow, 10px) var(--pv-primary, var(--primary));
      margin: 0 0 10px;
    }
    .pv-chips { display: flex; gap: 8px; }
    .pv-chip {
      flex: 1; height: 30px; border-radius: var(--pv-radius, 8px);
      display: flex; align-items: center; justify-content: center;
      font-size: 10px; font-weight: 700; color: #000;
    }

    .check-row { display: flex; align-items: center; gap: 10px; margin-top: 6px; }
    .check-row input { width: 18px; height: 18px; accent-color: var(--primary); }
    .check-row label { margin: 0; text-transform: none; letter-spacing: 0; font-size: 13px; color: var(--text); }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="logo">AETHERSTREAM</div>
      <div class="subtitle">Paramètres</div>
    </div>

    <div class="error-box" id="errBox"></div>

    <!-- ── THÈME ─────────────────────────────────────────────── -->
    <details open>
      <summary>Thème</summary>
      <div class="section-body">
        <div class="preview" id="preview">
          <div class="pv-title">AETHERSTREAM</div>
          <div class="pv-chips">
            <div class="pv-chip" id="pvC1">PRINCIPALE</div>
            <div class="pv-chip" id="pvC2">ACCENT</div>
            <div class="pv-chip" id="pvC3">TERTIAIRE</div>
          </div>
        </div>

        <div class="field">
          <label for="preset">Preset</label>
          <select id="preset" onchange="applyPreset()">
            <option value="">— Personnalisé —</option>
            $presetOptions
          </select>
        </div>

        <div class="row"><label>Couleur principale</label><input type="color" id="primary" value="$curPrimary" oninput="onThemeInput()"></div>
        <div class="row"><label>Couleur accent</label><input type="color" id="accent" value="$curAccent" oninput="onThemeInput()"></div>
        <div class="row"><label>Couleur tertiaire</label><input type="color" id="tertiary" value="$curTertiary" oninput="onThemeInput()"></div>
        <div class="row"><label>Intensité glow</label><input type="range" id="glow" min="0" max="1" step="0.05" value="$curGlow" oninput="onThemeInput()"></div>
        <div class="row"><label>Arrondi des coins</label><input type="range" id="radius" min="0" max="16" step="1" value="$curRadius" oninput="onThemeInput()"></div>

        <div class="field">
          <label for="mode">Mode d'affichage</label>
          <select id="mode">
            <option value="system">Système</option>
            <option value="dark">Sombre</option>
            <option value="light">Clair</option>
          </select>
        </div>
      </div>
    </details>

    <!-- ── TMDB ──────────────────────────────────────────────── -->
    <details>
      <summary>Clé TMDB</summary>
      <div class="section-body">
        <div class="field">
          <label for="tmdb">Bearer Token v4</label>
          <textarea id="tmdb" autocomplete="off" placeholder="${tmdbConfigured ? 'Déjà configurée — laisse vide pour ne pas changer' : 'eyJhbGciOiJIUzI1NiJ9…'}"></textarea>
          <div class="hint">
            Récupère ton token sur
            <a href="https://www.themoviedb.org/settings/api" target="_blank" style="color: var(--accent);">themoviedb.org/settings/api</a>
            (Read Access Token v4).
          </div>
        </div>
        ${tmdbConfigured ? '''<div class="check-row">
          <input type="checkbox" id="tmdbClear">
          <label for="tmdbClear">Supprimer la clé TMDB existante</label>
        </div>''' : ''}
      </div>
    </details>

    <!-- ── EPG XMLTV ─────────────────────────────────────────── -->
    <details>
      <summary>Guide des chaînes (EPG)</summary>
      <div class="section-body">
        <div class="check-row">
          <input type="checkbox" id="refreshXmltv">
          <label for="refreshXmltv">Rafraîchir le guide TNT France maintenant</label>
        </div>
      </div>
    </details>

    <button type="button" class="submit" id="submitBtn" onclick="submitForm()">Appliquer sur la TV</button>

    <p class="footer-note">
      Cette page est servie par ta TV.<br>
      Tes réglages restent sur ton réseau local.
    </p>
  </div>

  <script>
    const PRESETS = {$presetsJs};

    // Préselectionne le mode courant.
    document.getElementById('mode').value = '$curMode';

    function applyPreset() {
      const name = document.getElementById('preset').value;
      const p = PRESETS[name];
      if (!p) return;
      document.getElementById('primary').value = p.primary;
      document.getElementById('accent').value = p.accent;
      document.getElementById('tertiary').value = p.tertiary;
      document.getElementById('glow').value = p.glow;
      document.getElementById('radius').value = p.radius;
      document.getElementById('mode').value = p.mode;
      onThemeInput();
    }

    function onThemeInput() {
      const primary = document.getElementById('primary').value;
      const accent = document.getElementById('accent').value;
      const tertiary = document.getElementById('tertiary').value;
      const glow = parseFloat(document.getElementById('glow').value);
      const radius = parseFloat(document.getElementById('radius').value);
      const pv = document.getElementById('preview');
      pv.style.setProperty('--pv-primary', primary);
      pv.style.setProperty('--pv-radius', radius + 'px');
      pv.style.setProperty('--pv-glow', Math.round(glow * 20) + 'px');
      document.getElementById('pvC1').style.background = primary;
      document.getElementById('pvC2').style.background = accent;
      document.getElementById('pvC3').style.background = tertiary;
      // Dès qu'on touche un réglage manuel, on repasse en "Personnalisé".
      // (sauf si l'appel vient de applyPreset, qui resélectionne ensuite)
    }

    function showError(msg) {
      const box = document.getElementById('errBox');
      box.textContent = msg;
      box.classList.add('show');
      window.scrollTo({ top: 0, behavior: 'smooth' });
    }
    function hideError() { document.getElementById('errBox').classList.remove('show'); }

    async function submitForm() {
      hideError();
      const btn = document.getElementById('submitBtn');
      const payload = {
        theme: {
          primary: document.getElementById('primary').value,
          accent: document.getElementById('accent').value,
          tertiary: document.getElementById('tertiary').value,
          glow: parseFloat(document.getElementById('glow').value),
          radius: parseFloat(document.getElementById('radius').value),
          mode: document.getElementById('mode').value,
        },
        refreshXmltv: document.getElementById('refreshXmltv').checked,
      };

      const tmdbVal = (document.getElementById('tmdb').value || '').trim();
      const clearEl = document.getElementById('tmdbClear');
      if (clearEl && clearEl.checked) {
        payload.tmdb = '';
      } else if (tmdbVal) {
        if (tmdbVal.length < 20) return showError('Clé TMDB trop courte — vérifie le copier-coller.');
        payload.tmdb = tmdbVal;
      }

      btn.disabled = true;
      btn.textContent = 'Envoi en cours…';
      try {
        const res = await fetch('/submit?t=$token', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });
        if (res.ok) {
          document.documentElement.innerHTML = await res.text();
        } else {
          const j = await res.json().catch(() => ({ error: 'Erreur serveur.' }));
          showError(j.error || 'Erreur serveur.');
          btn.disabled = false;
          btn.textContent = 'Appliquer sur la TV';
        }
      } catch (e) {
        showError('Connexion perdue avec la TV.');
        btn.disabled = false;
        btn.textContent = 'Appliquer sur la TV';
      }
    }

    // Init preview.
    onThemeInput();
  </script>
</body>
</html>
''';
}

/// Page de confirmation affichée sur le mobile après submit OK.
String buildSuccessPage({required AppThemeConfig theme}) {
  return '''
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="dark">
  <title>AetherStream · OK</title>
  $_googleFontsLink
  <style>${_commonCss(theme)}</style>
</head>
<body>
  <div class="container" style="padding-top: 40px">
    <div class="success-icon"></div>
    <h1 class="success-title">CONFIGURATION ENVOYÉE</h1>
    <p class="success-body">
      Retourne sur ta TV — le compte<br>est en cours de chargement.<br><br>
      <span style="color: var(--text-dim); font-size: 12px;">Tu peux fermer cet onglet.</span>
    </p>
  </div>
</body>
</html>
''';
}

/// Page d'erreur (token invalide / expiré).
String buildErrorPage({required AppThemeConfig theme, required String message}) {
  return '''
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="dark">
  <title>AetherStream · Erreur</title>
  $_googleFontsLink
  <style>${_commonCss(theme)}</style>
</head>
<body>
  <div class="container" style="padding-top: 40px">
    <div class="header">
      <div class="logo" style="color: #ff6b6b; text-shadow: 0 0 16px rgba(255,107,107,0.4);">ERREUR</div>
    </div>
    <div class="card">
      <p style="margin: 0; text-align: center; color: var(--text-dim); line-height: 1.6;">$message</p>
    </div>
  </div>
</body>
</html>
''';
}
