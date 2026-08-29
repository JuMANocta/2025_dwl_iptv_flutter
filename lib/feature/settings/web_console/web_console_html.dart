import 'package:flutter/material.dart';

import '../../../core/themes/app_theme_config.dart';
import '../../../data/models/stream_account.dart';

/// Pages HTML de la console web (§webConsole — Phase 1).
///
/// Tout est auto-contenu (CSS inline, thémé via [AppThemeConfig]) pour rester
/// indépendant du pairing. Chaque vue est rendue côté serveur avec les données
/// injectées ; les actions passent par des POST `fetch()` JSON vers `/api/...`.

String _hex(Color c) {
  // ignore: deprecated_member_use
  final v = c.value & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0')}';
}

/// Échappe le HTML pour éviter qu'un libellé/URL casse la page.
String esc(String? s) {
  if (s == null) return '';
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

String _css(AppThemeConfig t) {
  final p = _hex(t.primaryColor);
  final a = _hex(t.accentColor);
  final ter = _hex(t.tertiaryColor);
  // ignore: deprecated_member_use
  final pv = t.primaryColor.value;
  final pRgb = '${(pv >> 16) & 0xFF}, ${(pv >> 8) & 0xFF}, ${pv & 0xFF}';
  final glowBlur = (20 * t.glowIntensity).round().clamp(0, 40);
  final glowAlpha = (0.45 * t.glowIntensity).clamp(0.0, 0.8);
  return '''
    :root {
      --p: $p; --a: $a; --ter: $ter;
      --bg: #050505; --surface: #121212; --surface-2: #1c1c1c;
      --text: #ffffff; --text-dim: #9a9a9a;
      --radius: ${t.borderRadius}px;
      --glow: 0 0 ${glowBlur}px rgba($pRgb, $glowAlpha);
    }
    * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
    html, body { margin: 0; padding: 0; min-height: 100vh; -webkit-font-smoothing: antialiased; }
    body {
      background:
        radial-gradient(ellipse at top, rgba(255,255,255,0.02) 0%, transparent 60%),
        var(--bg);
      color: var(--text);
      font-family: 'Source Code Pro', ui-monospace, 'SF Mono', Menlo, monospace;
      line-height: 1.5;
    }
    .wrap { max-width: 760px; margin: 0 auto; padding: 24px 16px 64px; }

    /* En-tête : wordmark "AetherStream" VT323 glow + sous-titre */
    header { text-align: center; margin-bottom: 28px; }
    header .logo {
      font-family: 'VT323', monospace; font-size: 44px; color: var(--p);
      letter-spacing: 3px; text-shadow: var(--glow); line-height: 1;
    }
    header h1 {
      font-size: 11px; margin: 6px 0 0; color: var(--text-dim);
      letter-spacing: 2px; text-transform: uppercase; font-weight: 700;
    }
    a { color: var(--a); text-decoration: none; }
    .back { display: inline-block; margin-bottom: 16px; font-size: 13px;
      letter-spacing: 1px; text-transform: uppercase; }
    .back:hover { color: var(--p); }

    /* Grille du dashboard : cartes "néon" */
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px,1fr)); gap: 12px; }
    .card {
      display: block; background: var(--surface);
      border: 1px solid rgba(255,255,255,0.06);
      border-radius: var(--radius); padding: 18px; transition: border-color .15s, box-shadow .15s;
      color: var(--text);
    }
    .card:hover, .card:focus {
      border-color: var(--p); box-shadow: var(--glow); outline: none;
    }
    .card .ic { font-size: 24px; line-height: 1; width: 44px; height: 44px;
      display: flex; align-items: center; justify-content: center;
      border-radius: calc(var(--radius) - 4px);
      background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.08); }
    .card .t { font-weight: 700; color: var(--text); margin-top: 12px;
      letter-spacing: .5px; }
    .card .s { font-size: 12px; color: var(--text-dim); margin-top: 4px; }

    /* Panneaux de section */
    .sec { background: var(--surface); border: 1px solid rgba(255,255,255,0.06);
      border-radius: var(--radius); padding: 20px; margin-bottom: 16px;
      box-shadow: var(--glow); }
    .sec h2 { font-size: 12px; margin: 0 0 14px; color: var(--p);
      letter-spacing: 1.5px; text-transform: uppercase; font-weight: 700; }

    /* Champs de saisie */
    label { display: block; font-size: 10px; color: var(--text-dim);
      margin: 12px 0 6px; letter-spacing: 1.5px; text-transform: uppercase;
      font-weight: 700; }
    input, select, textarea {
      width: 100%; background: var(--surface-2);
      border: 1px solid rgba(255,255,255,0.08); color: var(--text);
      border-radius: calc(var(--radius) - 2px); padding: 13px 14px;
      font-size: 15px; font-family: inherit; transition: border-color .15s, box-shadow .15s;
    }
    input:focus, select:focus, textarea:focus {
      outline: none; border-color: var(--p);
      box-shadow: 0 0 0 3px rgba(255,255,255,0.04), var(--glow);
    }

    /* Boutons */
    button {
      background: var(--p); color: #000; border: none;
      border-radius: var(--radius); padding: 14px 18px; font-size: 13px;
      font-weight: 800; letter-spacing: 2px; text-transform: uppercase;
      cursor: pointer; margin-top: 14px; box-shadow: var(--glow);
      transition: transform .1s;
      font-family: inherit;
    }
    button:active { transform: translateY(1px); }
    button.ghost { background: transparent; color: var(--a);
      border: 1px solid rgba(255,255,255,0.12); box-shadow: none; }
    button.danger { background: #ff4444; color: #fff; box-shadow: 0 0 18px rgba(255,68,68,0.4); }

    .row { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
    .acc { border: 1px solid rgba(255,255,255,0.08); border-radius: calc(var(--radius) - 2px);
      padding: 14px; margin-bottom: 10px; background: var(--surface-2); }
    .acc .nm { font-weight: 700; color: var(--text); letter-spacing: .5px; }
    .acc .meta { font-size: 12px; color: var(--text-dim); margin-top: 4px; word-break: break-all; }
    .badge { font-size: 10px; padding: 3px 9px; border-radius: 999px;
      background: rgba($pRgb, 0.15); color: var(--p);
      border: 1px solid rgba($pRgb, 0.4); letter-spacing: 1px;
      text-transform: uppercase; font-weight: 700; }

    /* Toast */
    .toast { position: fixed; left: 50%; bottom: 24px; transform: translateX(-50%);
      background: var(--surface); border: 1px solid var(--p); color: var(--text);
      padding: 12px 20px; border-radius: var(--radius); opacity: 0;
      transition: .2s; pointer-events: none; box-shadow: var(--glow);
      font-size: 13px; letter-spacing: .5px; }
    .toast.show { opacity: 1; }
    .hidden { display: none; }
    .muted { color: var(--text-dim); font-size: 13px; }

    /* Télécommande */
    .pad { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px;
      max-width: 320px; margin: 8px auto 18px; touch-action: manipulation; }
    .key { user-select: none; -webkit-user-select: none; touch-action: manipulation;
      background: var(--surface); border: 1px solid rgba(255,255,255,0.1);
      border-radius: var(--radius); color: var(--text); font-size: 26px;
      height: 78px; display: flex; align-items: center; justify-content: center;
      cursor: pointer; transition: .1s; }
    .key:active { background: var(--p); color: #000; transform: scale(.96);
      box-shadow: var(--glow); }
    .key.ok { background: var(--p); color: #000;
      font-weight: 700; font-size: 18px; letter-spacing: 1px; box-shadow: var(--glow); }
    .key.empty { background: transparent; border: none; pointer-events: none; }
    .bar { display: flex; gap: 10px; max-width: 320px; margin: 0 auto 12px; }
    .bar .key { flex: 1; height: 60px; font-size: 18px; }

    /* Groupes de dashboard (calqués sur les 3 sections de l'app) */
    .group { margin-bottom: 26px; }
    .ghead { display: flex; align-items: center; gap: 10px; margin: 0 2px 12px; }
    .ghead .gbar { width: 4px; height: 16px; border-radius: 2px; }
    .ghead .glbl { font-size: 11px; font-weight: 800; letter-spacing: 1.6px;
      text-transform: uppercase; }
    .group.g1 .gbar { background: var(--p); }   .group.g1 .glbl { color: var(--p); }
    .group.g2 .gbar { background: var(--a); }   .group.g2 .glbl { color: var(--a); }
    .group.g3 .gbar { background: var(--ter); } .group.g3 .glbl { color: var(--ter); }
    .group.g2 .card:hover, .group.g2 .card:focus { border-color: var(--a); }
    .group.g3 .card:hover, .group.g3 .card:focus { border-color: var(--ter); }

    /* Liste de cases à cocher (langues/régions) */
    .checks { margin-top: 8px; }
    .check { display: flex; align-items: center; gap: 12px; padding: 13px 4px;
      border-bottom: 1px solid rgba(255,255,255,0.06); font-size: 15px;
      color: var(--text); text-transform: none; letter-spacing: 0;
      margin: 0; font-weight: 400; cursor: pointer; }
    .check:last-child { border-bottom: none; }
    .check input { width: 20px; height: 20px; accent-color: var(--p); flex: 0 0 auto; }
  ''';
}

String _shell(AppThemeConfig t, String title, String body) => '''
<!DOCTYPE html>
<html lang="fr"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<meta name="color-scheme" content="dark">
<title>$title — AetherStream</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=VT323&family=Source+Code+Pro:wght@400;600;800&display=swap" rel="stylesheet">
<style>${_css(t)}</style>
</head><body>
<div class="wrap">
<header>
  <div class="logo">AetherStream</div>
  <h1>$title</h1>
</header>
$body
</div>
<div class="toast" id="toast"></div>
<script>
const T = new URLSearchParams(location.search).get('t') || '';
function toast(msg, ok=true){ const e=document.getElementById('toast');
  e.textContent=msg; e.style.borderColor = ok ? 'var(--p)' : '#ff4444';
  e.classList.add('show'); setTimeout(()=>e.classList.remove('show'), 2600); }
async function api(path, payload){
  const r = await fetch(path + '?t=' + encodeURIComponent(T), {
    method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify(payload||{}) });
  let j={}; try { j = await r.json(); } catch(e){}
  return { ok: r.ok && j.ok !== false, data: j };
}
</script>
</body></html>
''';

// ─── Dashboard ────────────────────────────────────────────────────────────────

String buildDashboard(AppThemeConfig t, String token) {
  // §webConsoleFix — Les href sont rendus côté serveur avec le token déjà
  // inclus (plus de réécriture JS fragile qui échouait car le `<script>` de
  // rewrite s'exécutait AVANT la définition de `T` placée en bas du shell).
  // §webConsoleDesign — Dashboard organisé comme les Paramètres de l'app : la
  // télécommande en tête (usage principal du téléphone), puis 3 groupes colorés
  // identiques à SettingsPage (vert Sources & comptes / cyan Affichage / magenta
  // Sauvegarde & application).
  final body = '''
  <p class="muted">Gère ta configuration AetherStream depuis ce navigateur. La TV reste synchronisée en direct.</p>

  <div class="group g1">
    <div class="ghead"><span class="gbar"></span><span class="glbl">Télécommande</span></div>
    <div class="grid">
      ${_navCard(token, 'remote', '🎮', 'Télécommande', 'Piloter la TV depuis ce téléphone')}
    </div>
  </div>

  <div class="group g1">
    <div class="ghead"><span class="gbar"></span><span class="glbl">Sources &amp; comptes</span></div>
    <div class="grid">
      ${_navCard(token, 'accounts', '📺', 'Comptes IPTV', 'Ajouter / modifier / recharger')}
      ${_navCard(token, 'tmdb', '🎬', 'Clé TMDB', 'Affiches & métadonnées')}
      ${_navCard(token, 'xmltv', '📡', 'Guide chaînes', 'EPG XMLTV — TNT France')}
    </div>
  </div>

  <div class="group g2">
    <div class="ghead"><span class="gbar"></span><span class="glbl">Affichage</span></div>
    <div class="grid">
      ${_navCard(token, 'langregion', '🌐', 'Langues / régions', 'Masquer le contenu étranger')}
      ${_navCard(token, 'theme', '🎨', 'Thème', 'Presets cyberpunk')}
    </div>
  </div>

  <div class="group g3">
    <div class="ghead"><span class="gbar"></span><span class="glbl">Sauvegarde &amp; application</span></div>
    <div class="grid">
      ${_navCard(token, 'backup', '💾', 'Sauvegarde', 'Importer / exporter .aether')}
      ${_navCard(token, 'about', 'ℹ️', 'À propos', 'Version & liens GitHub')}
      ${_navCard(token, 'logs', '📝', 'Journal', 'Diagnostic & touches télécommande')}
      ${_navCard(token, 'reset', '🧹', 'Réinitialiser', 'Vider favoris, reprises, historique')}
    </div>
  </div>
  ''';
  return _shell(t, 'Console web', body);
}

// ─── Vue « À propos » ────────────────────────────────────────────────────────

String buildAbout(AppThemeConfig t, String token, String version) {
  final body = '''
  ${_backLink(token)}
  <div class="sec">
    <h2>AetherStream</h2>
    <p class="muted">Client IPTV multi-comptes (Flutter Android) — playlist M3U,
      enrichissement TMDB, lecteur libmpv, téléchargements, EPG XMLTV.</p>
    <label>Version installée</label>
    <div class="acc"><div class="nm">${esc(version)}</div></div>
    <label>Liens</label>
    <div class="row">
      <a class="card" href="https://github.com/JuMANocta/2025_dwl_iptv_flutter" target="_blank">
        <div class="ic">⚙️</div><div class="t">Code source</div><div class="s">github.com</div>
      </a>
      <a class="card" href="https://github.com/JuMANocta/2025_dwl_iptv_flutter/releases" target="_blank">
        <div class="ic">🚀</div><div class="t">Releases</div><div class="s">Notes & APK</div>
      </a>
    </div>
  </div>
  ''';
  return _shell(t, 'À propos', body);
}

// ─── Journal de diagnostic (§tvLogs) ─────────────────────────────────────────

/// Vue « Journal » : la TV n'a pas de logcat accessible, donc tout ce que
/// l'application écrit via `debugPrint` atterrit ici, avec un export texte.
///
/// Le contenu arrive **déjà expurgé** (rédaction faite côté Dart, au niveau du
/// puits) : aucun identifiant IPTV ne transite sur le réseau local.
String buildLogs(AppThemeConfig t, String token, String content, bool keyTrace,
    int lineCount) {
  final tk = Uri.encodeQueryComponent(token);
  final body = '''
  ${_backLink(token)}
  <div class="sec">
    <h2>Journal de diagnostic</h2>
    <p class="muted">Tout ce que l'application écrit pendant son exécution.
      Les identifiants (URLs de playlist, mots de passe) sont masqués avant
      d'arriver ici.</p>
    <div class="row">
      <button class="btn" id="autoBtn" onclick="toggleAuto()">⏸️ Auto : ON</button>
      <button class="btn" id="keyBtn" onclick="toggleKeys()">
        ${keyTrace ? '⌨️ Touches + focus : ON' : '⌨️ Touches + focus : OFF'}</button>
      <a class="btn" href="/logs.txt?t=$tk" download="aetherstream-log.txt">⬇️ Télécharger</a>
      <button class="btn" onclick="clearLogs()">🧹 Vider</button>
    </div>
    <p class="muted" id="meta">$lineCount lignes</p>
    <pre id="log" class="log">${esc(content)}</pre>
  </div>
  <style>
    .log { max-height: 62vh; overflow: auto; white-space: pre-wrap;
           word-break: break-word; font-size: 12px; line-height: 1.45;
           background: rgba(0,0,0,.45); border: 1px solid var(--bd);
           border-radius: 10px; padding: 10px; margin-top: 10px; }
  </style>
  <script>
    let auto = true;
    let keys = ${keyTrace ? 'true' : 'false'};
    const logEl = () => document.getElementById('log');
    function atBottom(){ const e = logEl();
      return e.scrollTop + e.clientHeight >= e.scrollHeight - 24; }
    async function refresh(){
      try {
        const stick = atBottom();
        const r = await fetch('/logs.txt?t=' + encodeURIComponent(T));
        const txt = await r.text();
        const e = logEl();
        e.textContent = txt;
        document.getElementById('meta').textContent =
          txt.split('\\n').length + ' lignes';
        if (stick) e.scrollTop = e.scrollHeight;
      } catch (err) {}
    }
    function toggleAuto(){
      auto = !auto;
      document.getElementById('autoBtn').textContent =
        auto ? '⏸️ Auto : ON' : '▶️ Auto : OFF';
      if (auto) refresh();
    }
    async function toggleKeys(){
      keys = !keys;
      const r = await api('/api/logs/keytrace', { on: keys });
      document.getElementById('keyBtn').textContent =
        keys ? '⌨️ Touches + focus : ON' : '⌨️ Touches + focus : OFF';
      toast(keys ? 'Navigue à la télécommande : touches ET focus sont tracés'
                 : 'Traceur arrêté', r.ok);
      refresh();
    }
    async function clearLogs(){
      const r = await api('/api/logs/clear', {});
      toast(r.ok ? 'Journal vidé' : 'Échec', r.ok);
      refresh();
    }
    setInterval(() => { if (auto) refresh(); }, 2000);
    window.addEventListener('load', () => { const e = logEl(); e.scrollTop = e.scrollHeight; });
  </script>
  ''';
  return _shell(t, 'Journal', body);
}

String _navCard(String token, String view, String ic, String title, String sub) {
  final href = '/?t=${Uri.encodeQueryComponent(token)}&view=$view';
  return '<a class="card" href="$href">'
      '<div class="ic">$ic</div><div class="t">$title</div><div class="s">$sub</div></a>';
}

String _backLink(String token) =>
    '<a class="back" href="/?t=${Uri.encodeQueryComponent(token)}">← Console</a>';

// ─── Comptes ────────────────────────────────────────────────────────────────

String buildAccounts(AppThemeConfig t, String token, List<StreamAccount> accounts, String? currentId) {
  final sb = StringBuffer();
  if (accounts.isEmpty) {
    sb.write('<p class="muted">Aucun compte. Ajoute-en un ci-dessous.</p>');
  }
  for (final a in accounts) {
    final isCur = a.id == currentId;
    final mode = a.mode == StreamAuthMode.separate ? 'Xtream' : 'URL complète';
    final detail = a.mode == StreamAuthMode.separate
        ? esc(a.baseUrl ?? '')
        : esc(a.completeUrl ?? '');
    sb.write('''
    <div class="acc">
      <div class="row" style="justify-content:space-between">
        <span class="nm">${esc(a.label)}</span>
        ${isCur ? '<span class="badge">PRINCIPAL</span>' : ''}
      </div>
      <div class="meta">$mode · $detail</div>
      <div class="row">
        ${isCur ? '' : '<button class="ghost" onclick="setPrimary(\'${a.id}\')">Définir principal</button>'}
        <button class="ghost" onclick="reloadAcc('${a.id}')">Recharger</button>
        <button class="ghost" onclick="editAcc('${a.id}')">Modifier</button>
        <button class="danger" onclick="delAcc('${a.id}','${esc(a.label)}')">Supprimer</button>
      </div>
    </div>''');
  }

  // Données JSON pour pré-remplir le form d'édition.
  final accJson = '[${accounts.map((a) =>
      '{"id":"${a.id}","label":"${esc(a.label)}","mode":"${a.mode == StreamAuthMode.separate ? 'separate' : 'complete'}",'
      '"url":"${esc(a.completeUrl ?? '')}","base":"${esc(a.baseUrl ?? '')}",'
      '"user":"${esc(a.username ?? '')}","pass":"${esc(a.password ?? '')}"}').join(',')}]';

  final body = '''
  ${_backLink(token)}
  <div class="sec"><h2>Comptes</h2>$sb</div>
  <div class="sec">
    <h2 id="formTitle">Ajouter un compte</h2>
    <input type="hidden" id="aid" value="">
    <label>Nom</label>
    <input id="label" placeholder="Mon provider">
    <label>Type</label>
    <select id="mode" onchange="toggleMode()">
      <option value="complete">URL M3U complète</option>
      <option value="separate">Xtream Codes (serveur + identifiants)</option>
    </select>
    <div id="completeBox">
      <label>URL M3U</label>
      <input id="url" placeholder="http://serveur/get.php?username=...&password=...&type=m3u_plus">
    </div>
    <div id="separateBox" class="hidden">
      <label>URL serveur</label>
      <input id="base" placeholder="http://serveur:port">
      <label>Identifiant</label>
      <input id="user">
      <label>Mot de passe</label>
      <input id="pass">
    </div>
    <div class="row">
      <button onclick="saveAcc()">Enregistrer</button>
      <button class="ghost" onclick="resetForm()">Annuler</button>
    </div>
  </div>
  <script>
    const ACCS = $accJson;
    function toggleMode(){
      const sep = document.getElementById('mode').value === 'separate';
      document.getElementById('separateBox').classList.toggle('hidden', !sep);
      document.getElementById('completeBox').classList.toggle('hidden', sep);
    }
    function resetForm(){
      aid.value=''; label.value=''; url.value=''; base.value=''; user.value=''; pass.value='';
      document.getElementById('mode').value='complete'; toggleMode();
      document.getElementById('formTitle').textContent='Ajouter un compte';
    }
    function editAcc(id){
      const a = ACCS.find(x=>x.id===id); if(!a) return;
      aid.value=a.id; label.value=a.label; document.getElementById('mode').value=a.mode;
      url.value=a.url; base.value=a.base; user.value=a.user; pass.value=a.pass;
      toggleMode(); document.getElementById('formTitle').textContent='Modifier le compte';
      window.scrollTo(0, document.body.scrollHeight);
    }
    async function saveAcc(){
      const mode = document.getElementById('mode').value;
      const p = { id: aid.value, label: label.value, mode,
        url: url.value, base: base.value, user: user.value, pass: pass.value };
      const r = await api('/api/account/save', p);
      if(r.ok){ toast('✅ Enregistré'); setTimeout(()=>location.reload(), 600); }
      else toast(r.data.error || 'Erreur', false);
    }
    async function delAcc(id, name){
      if(!confirm('Supprimer "'+name+'" ?')) return;
      const r = await api('/api/account/delete', {id});
      if(r.ok){ toast('🗑️ Supprimé'); setTimeout(()=>location.reload(), 600); }
      else toast(r.data.error || 'Erreur', false);
    }
    async function setPrimary(id){
      const r = await api('/api/account/primary', {id});
      if(r.ok){ toast('✅ Principal'); setTimeout(()=>location.reload(), 600); }
      else toast(r.data.error || 'Erreur', false);
    }
    async function reloadAcc(id){
      toast('⏳ Rechargement…');
      const r = await api('/api/account/reload', {id});
      toast(r.ok ? '✅ Playlist rechargée' : (r.data.error||'Erreur'), r.ok);
    }
  </script>
  ''';
  return _shell(t, 'Comptes IPTV', body);
}

// ─── TMDB ────────────────────────────────────────────────────────────────────

String buildTmdb(AppThemeConfig t, String token, bool hasKey) {
  final body = '''
  ${_backLink(token)}
  <div class="sec">
    <h2>Clé API TMDB</h2>
    <p class="muted">${hasKey ? '✅ Une clé est déjà configurée.' : 'Aucune clé configurée.'} Colle ton <b>Bearer Token v4</b> (commence par eyJ...).</p>
    <label>Bearer Token</label>
    <textarea id="tok" rows="4" placeholder="eyJhbGciOi..."></textarea>
    <div class="row">
      <button onclick="saveTok()">Enregistrer</button>
      ${hasKey ? '<button class="danger" onclick="delTok()">Supprimer la clé</button>' : ''}
    </div>
  </div>
  <script>
    async function saveTok(){
      const token = tok.value.trim();
      if(token.length < 20){ toast('Token trop court', false); return; }
      const r = await api('/api/tmdb/save', {token});
      toast(r.ok ? '✅ Clé enregistrée' : (r.data.error||'Erreur'), r.ok);
    }
    async function delTok(){
      const r = await api('/api/tmdb/save', {token:''});
      if(r.ok){ toast('🗑️ Clé supprimée'); setTimeout(()=>location.reload(), 600); }
    }
  </script>
  ''';
  return _shell(t, 'Clé TMDB', body);
}

// ─── XMLTV ───────────────────────────────────────────────────────────────────

String buildXmltv(AppThemeConfig t, String token, DateTime? loadedAt, int channelCount) {
  final status = loadedAt == null
      ? 'Jamais chargé.'
      : 'Chargé : $channelCount chaînes (le ${loadedAt.day}/${loadedAt.month} à ${loadedAt.hour.toString().padLeft(2, '0')}:${loadedAt.minute.toString().padLeft(2, '0')}).';
  final body = '''
  ${_backLink(token)}
  <div class="sec">
    <h2>Guide des chaînes (XMLTV)</h2>
    <p class="muted">$status</p>
    <button onclick="refresh()">Rafraîchir le guide</button>
  </div>
  <script>
    async function refresh(){
      toast('⏳ Téléchargement…');
      const r = await api('/api/xmltv/refresh', {});
      toast(r.ok ? '✅ Guide rafraîchi' : (r.data.error||'Erreur'), r.ok);
      if(r.ok) setTimeout(()=>location.reload(), 800);
    }
  </script>
  ''';
  return _shell(t, 'Guide des chaînes', body);
}

// ─── Thème ───────────────────────────────────────────────────────────────────

String buildTheme(AppThemeConfig t, String token, List<String> presetNames, String currentName) {
  final opts = presetNames
      .map((n) => '<option value="${esc(n)}"${n == currentName ? ' selected' : ''}>${esc(n)}</option>')
      .join();
  final body = '''
  ${_backLink(token)}
  <div class="sec">
    <h2>Thème</h2>
    <p class="muted">Applique un preset cyberpunk. La TV change instantanément.</p>
    <label>Preset</label>
    <select id="preset">$opts</select>
    <button onclick="apply()">Appliquer</button>
  </div>
  <script>
    async function apply(){
      const r = await api('/api/theme/save', {preset: preset.value});
      toast(r.ok ? '🎨 Thème appliqué' : (r.data.error||'Erreur'), r.ok);
    }
  </script>
  ''';
  return _shell(t, 'Thème', body);
}

// ─── Langues / régions ─────────────────────────────────────────────────────────

/// §webConsoleLangFilter — Vue de masquage des langues/régions (miroir de
/// `RegionFilterPage`). [hidden] = régions actuellement masquées (cochées).
String buildRegions(
    AppThemeConfig t, String token, List<String> labels, Set<String> hidden) {
  final rows = labels.map((r) {
    final checked = hidden.contains(r) ? ' checked' : '';
    return '<label class="check">'
        '<input type="checkbox" class="rg" value="${esc(r)}"$checked>'
        '<span>${esc(r)}</span></label>';
  }).join();
  final body = '''
  ${_backLink(token)}
  <div class="sec">
    <h2>Langues / régions</h2>
    <p class="muted">Coche les langues/régions à <b>masquer</b> du catalogue. Le
      contenu français (|FR|), québécois et VOSTFR est toujours conservé.<br>
      La mémoire est allégée dès « Appliquer » ; la taille sur disque diminue au
      prochain rechargement de la playlist.</p>
    <div class="row" style="gap:8px; margin-top:6px">
      <button class="ghost" onclick="setAll(true)">Tout masquer</button>
      <button class="ghost" onclick="setAll(false)">Tout afficher</button>
    </div>
    <div class="checks">$rows</div>
    <button onclick="saveRegions()">Appliquer</button>
  </div>
  <script>
    function setAll(v){ document.querySelectorAll('.rg').forEach(c=>c.checked=v); }
    async function saveRegions(){
      const hidden = Array.from(document.querySelectorAll('.rg:checked')).map(c=>c.value);
      toast('⏳ Application…');
      const r = await api('/api/regions/save', {hidden});
      toast(r.ok ? '✅ Filtre appliqué — catalogue rechargé' : (r.data.error||'Erreur'), r.ok);
    }
  </script>
  ''';
  return _shell(t, 'Langues / régions', body);
}

// ─── Sauvegarde ────────────────────────────────────────────────────────────────

String buildBackup(AppThemeConfig t, String token) {
  final body = '''
  ${_backLink(token)}
  <div class="sec">
    <h2>Importer une sauvegarde</h2>
    <p class="muted">Sélectionne un fichier <b>.aether</b> et saisis son mot de passe. ⚠️ Écrase la configuration actuelle.</p>
    <label>Fichier .aether</label>
    <input type="file" id="file" accept=".aether">
    <label>Mot de passe</label>
    <input type="password" id="ipw">
    <button class="danger" onclick="doImport()">Restaurer</button>
  </div>
  <div class="sec">
    <h2>Exporter une sauvegarde</h2>
    <p class="muted">Choisis un mot de passe : il chiffrera la sauvegarde (AES-256). Garde-le, il n'est pas stocké.</p>
    <label>Mot de passe</label>
    <input type="password" id="epw">
    <button onclick="doExport()">Générer & télécharger</button>
  </div>
  <script>
    function readFileB64(f){ return new Promise((res,rej)=>{
      const r=new FileReader(); r.onload=()=>res(r.result.split(',')[1]); r.onerror=rej;
      r.readAsDataURL(f); }); }
    async function doImport(){
      const f = file.files[0];
      if(!f){ toast('Choisis un fichier', false); return; }
      if(ipw.value.length < 1){ toast('Mot de passe requis', false); return; }
      toast('⏳ Restauration…');
      const data = await readFileB64(f);
      const r = await api('/api/backup/import', {password: ipw.value, data});
      toast(r.ok ? '✅ Restauré' : (r.data.error||'Mot de passe incorrect ?'), r.ok);
    }
    async function doExport(){
      if(epw.value.length < 1){ toast('Mot de passe requis', false); return; }
      toast('⏳ Génération…');
      const r = await api('/api/backup/export', {password: epw.value});
      if(!r.ok){ toast(r.data.error||'Erreur', false); return; }
      const bin = atob(r.data.data);
      const arr = new Uint8Array(bin.length);
      for(let i=0;i<bin.length;i++) arr[i]=bin.charCodeAt(i);
      const blob = new Blob([arr], {type:'application/octet-stream'});
      const a=document.createElement('a'); a.href=URL.createObjectURL(blob);
      a.download=r.data.filename||'backup.aether'; a.click();
      toast('✅ Téléchargé');
    }
  </script>
  ''';
  return _shell(t, 'Sauvegarde', body);
}

// ─── Télécommande ──────────────────────────────────────────────────────────────

String buildRemote(AppThemeConfig t, String token) {
  final body = '''
  ${_backLink(token)}
  <div class="sec">
    <h2>Télécommande</h2>
    <p class="muted">Pilote l'interface de la TV. Pendant la lecture : ←/→ = ±10s, ↑/↓ = volume, OK = pause.</p>
    <div class="pad">
      <div class="key empty"></div>
      <div class="key" onclick="rk('up')">▲</div>
      <div class="key empty"></div>
      <div class="key" onclick="rk('left')">◀</div>
      <div class="key ok" onclick="rk('ok')">OK</div>
      <div class="key" onclick="rk('right')">▶</div>
      <div class="key empty"></div>
      <div class="key" onclick="rk('down')">▼</div>
      <div class="key empty"></div>
    </div>
    <div class="bar">
      <div class="key" onclick="rk('back')">↩ Retour</div>
      <div class="key" onclick="rk('menu')">☰ Menu</div>
    </div>
    <div class="bar">
      <div class="key" onclick="rk('seekback')">⏪ 10s</div>
      <div class="key" onclick="rk('playpause')">⏯</div>
      <div class="key" onclick="rk('seekfwd')">10s ⏩</div>
    </div>
    <div class="bar">
      <div class="key" onclick="rk('voldown')">🔉 −</div>
      <div class="key" onclick="rk('volup')">🔊 +</div>
    </div>
  </div>
  <script>
    let busy = false;
    async function rk(key){
      if(busy) return; busy = true;
      try { await fetch('/api/remote?t=' + encodeURIComponent(T), {
        method:'POST', headers:{'Content-Type':'application/json'},
        body: JSON.stringify({key}) }); } catch(e){}
      busy = false;
    }
  </script>
  ''';
  return _shell(t, 'Télécommande', body);
}

// ─── Réinitialiser les données d'usage ──────────────────────────────────────────

/// §webConsoleReset — Vue de remise à zéro des données d'usage (miroir de la
/// tuile « Réinitialiser les données d'usage » de SettingsPage). Action
/// destructive → bouton danger + `confirm()` JS côté navigateur.
String buildReset(AppThemeConfig t, String token) {
  final body = '''
  ${_backLink(token)}
  <div class="sec">
    <h2>Réinitialiser les données d'usage</h2>
    <p class="muted">Vide les <b>favoris</b>, les <b>reprises</b> de lecture
      (films &amp; séries), l'<b>historique de recherche</b> et la
      <b>dernière chaîne</b> regardée.<br>
      Conserve les comptes IPTV, la clé TMDB, le thème et les filtres
      langues/régions.<br>
      <b>Cette action est irréversible.</b></p>
    <button class="danger" onclick="doReset()">Tout réinitialiser</button>
  </div>
  <script>
    async function doReset(){
      if(!confirm("Vider favoris, reprises et historique ? Action irréversible.")) return;
      toast('⏳ Réinitialisation…');
      const r = await api('/api/reset', {});
      toast(r.ok ? '🧹 Données réinitialisées' : (r.data.error||'Erreur'), r.ok);
    }
  </script>
  ''';
  return _shell(t, 'Réinitialiser', body);
}

String buildErrorPage(AppThemeConfig t, String message) =>
    _shell(t, 'Erreur', '<div class="sec"><p>${esc(message)}</p></div>');
