import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/themes/light_palette.dart';
import '../core/utils/platform_tv.dart';
import '../l10n/l10n_ext.dart';
import 'tv/tv_stepper_row.dart';

/// §themeStudio — Choisir une couleur QUELCONQUE, sans paquet.
///
/// **Le défaut corrigé (signalé le 2026-09-16)** : la page des thèmes ne
/// proposait que 14 pastilles en dur. Une couleur hors de cette liste n'était
/// atteignable que par un préréglage, ou par une sauvegarde `.aether`
/// restaurée — autrement dit, pas du tout.
///
/// Deux entrées, pour deux façons de savoir ce qu'on veut :
///   - la ROUE (teinte en angle, saturation en rayon) + un curseur de
///     luminosité, pour chercher à l'œil ;
///   - le CODE `#RRGGBB`, pour reproduire une couleur qu'on connaît déjà.
///
/// ⚠️ Sur TÉLÉVISEUR, la roue est remplacée par trois pas-à-pas focusables :
/// viser un point dans un disque à la télécommande n'a aucun sens (même
/// constat que le `Slider`, §3c-bis #5).
///
/// ⚠️ La couleur choisie n'est pas « posée telle quelle » sur un fond clair :
/// elle passe par la même dérivation de contraste que les autres
/// (`themedOnSurface` / `readableOn`, §lightTheme). Rien de spécial à faire
/// ici — c'est le rôle des alias de `colors.dart`.

// ── Conversions, pures et testées ───────────────────────────────────────────

/// Le code `#RRGGBB` de [c], en majuscules. L'alpha est ignoré : la palette du
/// thème est faite de couleurs opaques.
String hexOfColor(Color c) {
  // ignore: deprecated_member_use
  final int rgb = c.value & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).toUpperCase().padLeft(6, '0')}';
}

/// [text] lu comme une couleur, ou `null` s'il n'en est pas une.
///
/// Tolère le `#` absent, les espaces autour et la casse. ⛔ Refuse tout le
/// reste — trois chiffres (`#0F0`), huit (un alpha), un nom de couleur : mieux
/// vaut un champ qui dit « non » qu'un champ qui devine.
Color? parseHexColor(String text) {
  final String s = text.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s)) return null;
  return Color(0xFF000000 | int.parse(s, radix: 16));
}

/// Ouvre le sélecteur et rend la couleur choisie, ou `null` si on annule.
Future<Color?> showColorWheelSheet(
  BuildContext context, {
  required Color initial,
  required String title,
}) {
  return showDialog<Color>(
    context: context,
    builder: (ctx) => _ColorWheelDialog(initial: initial, title: title),
  );
}

class _ColorWheelDialog extends StatefulWidget {
  final Color initial;
  final String title;

  const _ColorWheelDialog({required this.initial, required this.title});

  @override
  State<_ColorWheelDialog> createState() => _ColorWheelDialogState();
}

class _ColorWheelDialogState extends State<_ColorWheelDialog> {
  late HSLColor _hsl;
  late TextEditingController _hex;
  bool _hexError = false;

  @override
  void initState() {
    super.initState();
    _hsl = HSLColor.fromColor(widget.initial);
    _hex = TextEditingController(text: hexOfColor(widget.initial));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  Color get _color => _hsl.toColor();

  /// Une seule porte d'entrée pour les deux moyens de choisir : la roue écrit
  /// le code, le code écrit la roue. Sans ça, les deux se contrediraient à
  /// l'écran (c'est le défaut qu'on vient de corriger côté aperçu).
  void _setHsl(HSLColor next, {bool syncField = true}) {
    setState(() {
      _hsl = next;
      _hexError = false;
      if (syncField) _hex.text = hexOfColor(next.toColor());
    });
  }

  void _onHexChanged(String raw) {
    final Color? parsed = parseHexColor(raw);
    if (parsed == null) {
      setState(() => _hexError = raw.trim().isNotEmpty);
      return;
    }
    _setHsl(HSLColor.fromColor(parsed), syncField: false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool isTv = PlatformTv.isTv;

    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _swatch(cs),
              const SizedBox(height: 14),
              if (isTv) ..._tvSteppers(context) else ..._touchWheel(context),
              const SizedBox(height: 12),
              TextField(
                controller: _hex,
                onChanged: _onHexChanged,
                maxLength: 7,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
                ],
                decoration: InputDecoration(
                  labelText: context.l10n.themeHex,
                  counterText: '',
                  errorText: _hexError ? context.l10n.themeHexInvalid : null,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          // §safeFocus — le focus s'ouvre sur le bouton SÛR.
          autofocus: true,
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _color),
          child: Text(context.l10n.commonApply),
        ),
      ],
    );
  }

  /// L'aperçu de la couleur, avec son code écrit DESSUS : `onColorFor` choisit
  /// le noir ou le blanc — un code illisible sur sa propre couleur serait une
  /// jolie ironie.
  Widget _swatch(ColorScheme cs) => Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Text(
          hexOfColor(_color),
          style: TextStyle(
            color: onColorFor(_color),
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      );

  List<Widget> _touchWheel(BuildContext context) => [
        Center(
          child: _HueSaturationWheel(
            hsl: _hsl,
            size: 200,
            onChanged: (h, s) => _setHsl(_hsl.withHue(h).withSaturation(s)),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(width: 78, child: Text(context.l10n.themeLightness)),
            Expanded(
              child: Slider(
                value: _hsl.lightness,
                onChanged: (v) => _setHsl(_hsl.withLightness(v)),
              ),
            ),
          ],
        ),
      ];

  List<Widget> _tvSteppers(BuildContext context) => [
        _tvRow(context, context.l10n.themeHue, _hsl.hue, 0, 359, 5,
            (v) => _setHsl(_hsl.withHue(v))),
        _tvRow(context, context.l10n.themeSaturation, _hsl.saturation, 0, 1,
            0.05, (v) => _setHsl(_hsl.withSaturation(v))),
        _tvRow(context, context.l10n.themeLightness, _hsl.lightness, 0, 1, 0.05,
            (v) => _setHsl(_hsl.withLightness(v))),
      ];

  Widget _tvRow(BuildContext context, String label, double value, double min,
          double max, double step, ValueChanged<double> onChanged) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
                width: 78,
                child: Text(label, style: const TextStyle(fontSize: 13))),
            Expanded(
              child: TvStepperRow(
                value: value,
                min: min,
                max: max,
                step: step,
                color: _color,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      );
}

/// La roue : teinte en ANGLE, saturation en RAYON, à la luminosité courante.
class _HueSaturationWheel extends StatelessWidget {
  final HSLColor hsl;
  final double size;

  /// Rend (teinte 0-360, saturation 0-1).
  final void Function(double hue, double saturation) onChanged;

  const _HueSaturationWheel({
    required this.hsl,
    required this.size,
    required this.onChanged,
  });

  void _pick(Offset local) {
    final double r = size / 2;
    final Offset v = local - Offset(r, r);
    final double dist = v.distance;
    // atan2 rend −π..π ; on ramène en 0..360 pour coller à `HSLColor.hue`.
    final double hue = (math.atan2(v.dy, v.dx) * 180 / math.pi + 360) % 360;
    onChanged(hue, (dist / r).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (d) => _pick(d.localPosition),
      onPanUpdate: (d) => _pick(d.localPosition),
      child: CustomPaint(
        size: Size.square(size),
        painter: _WheelPainter(hsl),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final HSLColor hsl;

  const _WheelPainter(this.hsl);

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Offset center = rect.center;
    final double radius = size.width / 2;

    // Teintes en couronne : 0° à droite, pour correspondre à `atan2`.
    final List<Color> hues = [
      for (int i = 0; i <= 360; i += 30)
        HSLColor.fromAHSL(1, (i % 360).toDouble(), 1, hsl.lightness).toColor(),
    ];
    canvas.drawCircle(
      center,
      radius,
      Paint()..shader = SweepGradient(colors: hues).createShader(rect),
    );

    // Saturation en rayon : au centre, le gris de MÊME luminosité (saturation
    // 0), qui s'efface vers le bord.
    final Color grey = HSLColor.fromAHSL(1, 0, 0, hsl.lightness).toColor();
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(colors: [grey, grey.withAlpha(0)])
            .createShader(rect),
    );

    // Le repère de la couleur courante — sans lui, la roue ne dit pas où l'on
    // est, seulement où l'on peut aller.
    final double a = hsl.hue * math.pi / 180;
    final Offset knob = center +
        Offset(math.cos(a), math.sin(a)) * (hsl.saturation * radius);
    canvas.drawCircle(
        knob,
        9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = onColorFor(hsl.toColor()));
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.hsl != hsl;
}
