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
      const payload = {
        mode,
        label: document.getElementById('label').value,
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
