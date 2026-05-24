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
  return '''
    :root { --p: $p; --a: $a; --ter: $ter; }
    * { box-sizing: border-box; }
    body {
      margin: 0; padding: 0; background: #0b0d0f; color: #e8eaed;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      line-height: 1.5;
    }
    .wrap { max-width: 760px; margin: 0 auto; padding: 20px 16px 64px; }
    header { display: flex; align-items: center; gap: 12px; margin-bottom: 18px; }
    header h1 { font-size: 20px; margin: 0; color: #fff; }
    .logo { width: 34px; height: 34px; border-radius: 8px;
      background: linear-gradient(135deg, var(--p), var(--a));
      box-shadow: 0 0 16px ${_hex(t.primaryColor)}66; }
    a { color: var(--a); text-decoration: none; }
    .back { display: inline-block; margin-bottom: 16px; font-size: 14px; }
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px,1fr)); gap: 12px; }
    .card {
      display: block; background: #15191d; border: 1px solid #23282e;
      border-radius: 14px; padding: 16px; transition: .15s;
    }
    .card:hover { border-color: var(--p); box-shadow: 0 0 14px ${_hex(t.primaryColor)}44; }
    .card .ic { font-size: 26px; }
    .card .t { font-weight: 600; color: #fff; margin-top: 8px; }
    .card .s { font-size: 12px; color: #9aa0a6; margin-top: 2px; }
    .sec { background: #15191d; border: 1px solid #23282e; border-radius: 14px;
      padding: 16px; margin-bottom: 16px; }
    .sec h2 { font-size: 15px; margin: 0 0 12px; color: var(--p);
      letter-spacing: .5px; text-transform: uppercase; }
    label { display: block; font-size: 12px; color: #9aa0a6; margin: 10px 0 4px; }
    input, select, textarea {
      width: 100%; background: #0b0d0f; border: 1px solid #2c333a; color: #fff;
      border-radius: 10px; padding: 11px 12px; font-size: 15px; font-family: inherit;
    }
    input:focus, select:focus, textarea:focus { outline: none; border-color: var(--p); }
    button {
      background: linear-gradient(135deg, var(--p), var(--a)); color: #0b0d0f;
      border: none; border-radius: 10px; padding: 12px 18px; font-size: 15px;
      font-weight: 700; cursor: pointer; margin-top: 14px;
    }
    button.ghost { background: transparent; color: var(--a); border: 1px solid #2c333a; }
    button.danger { background: linear-gradient(135deg, #ff4444, #c71585); color: #fff; }
    .row { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
    .acc { border: 1px solid #23282e; border-radius: 12px; padding: 12px; margin-bottom: 10px; }
    .acc .nm { font-weight: 600; color: #fff; }
    .acc .meta { font-size: 12px; color: #9aa0a6; margin-top: 2px; word-break: break-all; }
    .badge { font-size: 11px; padding: 2px 8px; border-radius: 6px;
      background: ${_hex(t.primaryColor)}22; color: var(--p); border: 1px solid ${_hex(t.primaryColor)}55; }
    .toast { position: fixed; left: 50%; bottom: 20px; transform: translateX(-50%);
      background: #15191d; border: 1px solid var(--p); color: #fff; padding: 12px 18px;
      border-radius: 10px; opacity: 0; transition: .2s; pointer-events: none; }
    .toast.show { opacity: 1; }
    .hidden { display: none; }
    .muted { color: #9aa0a6; font-size: 13px; }
    /* Télécommande */
    .pad { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px;
      max-width: 320px; margin: 8px auto 18px; touch-action: manipulation; }
    .key { user-select: none; -webkit-user-select: none; touch-action: manipulation;
      background: #15191d; border: 1px solid #2c333a; border-radius: 14px;
      color: #fff; font-size: 26px; height: 78px; display: flex;
      align-items: center; justify-content: center; cursor: pointer; }
    .key:active { background: var(--p); color: #0b0d0f; transform: scale(.96); }
    .key.ok { background: linear-gradient(135deg, var(--p), var(--a)); color: #0b0d0f;
      font-weight: 700; font-size: 18px; }
    .key.empty { background: transparent; border: none; pointer-events: none; }
    .bar { display: flex; gap: 10px; max-width: 320px; margin: 0 auto 12px; }
    .bar .key { flex: 1; height: 60px; font-size: 18px; }
  ''';
}

String _shell(AppThemeConfig t, String title, String body) => '''
<!DOCTYPE html>
<html lang="fr"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<title>$title — AetherStream</title>
<style>${_css(t)}</style>
</head><body>
<div class="wrap">
<header><div class="logo"></div><h1>$title</h1></header>
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

String buildDashboard(AppThemeConfig t) {
  // Les href des cartes sont réécrits avec le token via JS au chargement.
  final body = '''
  <p class="muted">Gère ta configuration AetherStream depuis ce navigateur. La TV reste synchronisée en direct.</p>
  <div class="grid" id="grid">
    ${_navCard('accounts', '📺', 'Comptes IPTV', 'Ajouter / modifier / recharger')}
    ${_navCard('tmdb', '🎬', 'Clé TMDB', 'Affiches & métadonnées')}
    ${_navCard('xmltv', '📡', 'Guide chaînes', 'EPG XMLTV — TNT France')}
    ${_navCard('theme', '🎨', 'Thème', 'Presets cyberpunk')}
    ${_navCard('backup', '💾', 'Sauvegarde', 'Importer / exporter .aether')}
    ${_navCard('remote', '🎮', 'Télécommande', 'Piloter la TV depuis ce tél.')}
  </div>
  <script>
    document.querySelectorAll('[data-view]').forEach(el=>{
      el.href = '/?t=' + encodeURIComponent(T) + '&view=' + el.dataset.view;
    });
  </script>
  ''';
  return _shell(t, 'Console web', body);
}

String _navCard(String view, String ic, String title, String sub) =>
    '<a class="card" data-view="$view" href="#">'
    '<div class="ic">$ic</div><div class="t">$title</div><div class="s">$sub</div></a>';

String _backLink() =>
    '<a class="back" data-home href="#">← Console</a>'
    '<script>document.querySelector("[data-home]").href="/?t="+encodeURIComponent(T);</script>';

// ─── Comptes ────────────────────────────────────────────────────────────────

String buildAccounts(AppThemeConfig t, List<StreamAccount> accounts, String? currentId) {
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
  ${_backLink()}
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

String buildTmdb(AppThemeConfig t, bool hasKey) {
  final body = '''
  ${_backLink()}
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

String buildXmltv(AppThemeConfig t, DateTime? loadedAt, int channelCount) {
  final status = loadedAt == null
      ? 'Jamais chargé.'
      : 'Chargé : $channelCount chaînes (le ${loadedAt.day}/${loadedAt.month} à ${loadedAt.hour.toString().padLeft(2, '0')}:${loadedAt.minute.toString().padLeft(2, '0')}).';
  final body = '''
  ${_backLink()}
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

String buildTheme(AppThemeConfig t, List<String> presetNames, String currentName) {
  final opts = presetNames
      .map((n) => '<option value="${esc(n)}"${n == currentName ? ' selected' : ''}>${esc(n)}</option>')
      .join();
  final body = '''
  ${_backLink()}
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

// ─── Sauvegarde ────────────────────────────────────────────────────────────────

String buildBackup(AppThemeConfig t) {
  final body = '''
  ${_backLink()}
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

String buildRemote(AppThemeConfig t) {
  final body = '''
  ${_backLink()}
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

String buildErrorPage(AppThemeConfig t, String message) =>
    _shell(t, 'Erreur', '<div class="sec"><p>${esc(message)}</p></div>');
