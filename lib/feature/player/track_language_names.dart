import '../../l10n/l10n_ext.dart';

/// R43 — Noms et codes courts des langues de pistes, sortis de la feuille de
/// pistes parce que la tuile « Langues des pistes » des Réglages en a besoin
/// aussi : une mémoire qui se voit doit se nommer au même endroit qu'au
/// lecteur (« Anglais », pas « en »).

/// Code court 2 lettres pour le badge (ex. « FR »). Repli : 2 premières
/// lettres du code en majuscules, ou « ? ».
String trackLanguageShort(String? code) {
  if (code == null || code.trim().isEmpty) return '?';
  final c = code.toLowerCase().trim();
  if (_kNoLanguage.contains(c)) return '?';
  const map = {
    'fr': 'FR',
    'fre': 'FR',
    'fra': 'FR',
    'en': 'EN',
    'eng': 'EN',
    'es': 'ES',
    'spa': 'ES',
    'de': 'DE',
    'ger': 'DE',
    'deu': 'DE',
    'it': 'IT',
    'ita': 'IT',
    'pt': 'PT',
    'por': 'PT',
    'ar': 'AR',
    'ara': 'AR',
    'ru': 'RU',
    'rus': 'RU',
    'nl': 'NL',
    'dut': 'NL',
    'nld': 'NL',
    'ja': 'JA',
    'jpn': 'JA',
    'zh': 'ZH',
    'chi': 'ZH',
    'zho': 'ZH',
    'ko': 'KO',
    'kor': 'KO',
    'tr': 'TR',
    'tur': 'TR',
    'pl': 'PL',
    'pol': 'PL',
  };
  return map[c] ?? c.substring(0, c.length >= 2 ? 2 : 1).toUpperCase();
}

/// R43 — Ce que le natif renvoie quand une piste n'a PAS de langue
/// (`format.language ?: "unknown"`), et l'ISO « indéterminé ». Ce ne sont pas
/// des langues : la piste se nomme alors par son titre ou son numéro, jamais
/// « UNKNOWN ».
const Set<String> _kNoLanguage = {'unknown', 'und'};

/// Mappe les codes ISO 639 (les conteneurs portent souvent du 639-2/B : fre,
/// ger…) vers un libellé lisible. Repli : code en majuscules ; `null` sans code.
String? trackLanguageName(String? code) {
  if (code == null || code.trim().isEmpty) return null;
  final c = code.toLowerCase().trim();
  if (_kNoLanguage.contains(c)) return null;
  // §l10nAll — Le CODE reste la clé (stable) ; le nom vient de la l10n.
  final l10n = L10n.current;
  return switch (c) {
    'fr' || 'fre' || 'fra' => l10n.langFrench,
    'en' || 'eng' => l10n.langEnglish,
    'es' || 'spa' => l10n.langSpanish,
    'de' || 'ger' || 'deu' => l10n.langGerman,
    'it' || 'ita' => l10n.langItalian,
    'pt' || 'por' => l10n.langPortuguese,
    'ar' || 'ara' => l10n.langArabic,
    'ru' || 'rus' => l10n.langRussian,
    'nl' || 'dut' || 'nld' => l10n.langDutch,
    'ja' || 'jpn' => l10n.langJapanese,
    'zh' || 'chi' || 'zho' => l10n.langChinese,
    'ko' || 'kor' => l10n.langKorean,
    'tr' || 'tur' => l10n.langTurkish,
    'pl' || 'pol' => l10n.langPolish,
    'vostfr' => 'VOSTFR',
    _ => code.toUpperCase(),
  };
}
