import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/themes/colors.dart';
import '../../data/services/replay_service.dart';
import '../../data/services/xmltv_service.dart';
import '../../data/models/xmltv_program.dart';

/// Sheet permettant à l'utilisateur de choisir manuellement
/// un jour, une heure et une durée pour lancer un replay.
///
/// Si [tvgId] est fourni et que des données XMLTV sont disponibles,
/// une grille de programmes est affichée au-dessus du picker manuel.
/// Tapper un programme lance directement le replay.
///
/// Si [streams] contient plusieurs options, un sélecteur de qualité est affiché.
/// Retourne un [ReplayProgram] synthétique avec le stream sélectionné.
class ReplayDatePickerSheet extends StatefulWidget {
  final int? catchupDays;
  /// Liste des streams disponibles pour le replay (multi-qualité).
  final List<ReplayStreamOption> streams;
  /// tvg-id de la chaîne — utilisé pour charger les programmes XMLTV.
  final String? tvgId;

  const ReplayDatePickerSheet({
    super.key,
    this.catchupDays,
    this.streams = const [],
    this.tvgId,
  });

  @override
  State<ReplayDatePickerSheet> createState() => _ReplayDatePickerSheetState();
}

class _ReplayDatePickerSheetState extends State<ReplayDatePickerSheet> {
  // ---- Sélections partagées ----
  late DateTime _selectedDay;   // minuit du jour choisi

  // ---- Picker manuel ----
  late TimeOfDay _selectedTime; // heure de début
  int _durationMinutes = 60;    // durée sélectionnée
  int _selectedStreamIndex = 0; // index dans widget.streams

  // ---- XMLTV ----
  List<XmltvProgram> _xmltvPrograms = [];
  bool _isLoadingXmltv = false;
  Set<DateTime> _daysWithData = {};

  static const _durations = [30, 60, 90, 120, 180];

  ReplayStreamOption? get _selectedStream =>
      widget.streams.isEmpty ? null : widget.streams[_selectedStreamIndex];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Par défaut : hier, heure actuelle arrondie à la demi-heure précédente
    _selectedDay = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    final roundedMinute = now.minute >= 30 ? 30 : 0;
    _selectedTime = TimeOfDay(hour: now.hour, minute: roundedMinute);
    _initXmltv();
  }

  // ---- XMLTV ----

  /// Charge en parallèle les jours disponibles + les programmes du jour initial.
  Future<void> _initXmltv() async {
    if (widget.tvgId == null) return;
    setState(() => _isLoadingXmltv = true);
    final results = await Future.wait([
      XmltvService.getAvailableDays(widget.tvgId!),
      XmltvService.getProgramsForDay(widget.tvgId!, _selectedDay),
    ]);
    if (mounted) {
      setState(() {
        _daysWithData = results[0] as Set<DateTime>;
        _xmltvPrograms = results[1] as List<XmltvProgram>;
        _isLoadingXmltv = false;
      });
    }
  }

  Future<void> _loadXmltvPrograms() async {
    if (widget.tvgId == null) return;
    setState(() => _isLoadingXmltv = true);
    final programs = await XmltvService.getProgramsForDay(widget.tvgId!, _selectedDay);
    if (mounted) {
      setState(() {
        _xmltvPrograms = programs;
        _isLoadingXmltv = false;
      });
    }
  }

  void _onDayChanged(DateTime d) {
    setState(() => _selectedDay = d);
    _loadXmltvPrograms();
  }

  // Appelé quand l'utilisateur tape sur un programme dans la grille XMLTV.
  void _confirmFromXmltv(XmltvProgram program) {
    final now = DateTime.now();
    var start = program.start;
    // Sécurité : start ne peut pas être dans le futur
    if (start.isAfter(now)) start = now.subtract(const Duration(minutes: 5));
    // Pour un programme encore en cours, on borne la fin à maintenant
    final end = program.stop.isAfter(now) ? now : program.stop;
    final stream = _selectedStream;
    Navigator.of(context).pop(ReplayProgram(
      title: program.title,
      start: start,
      end: end,
      description: program.description ?? '',
      hasArchive: true,
      selectedStreamId: stream?.streamId,
      selectedStreamUrl: stream?.streamUrl,
      selectedCatchupSource: stream?.catchupSource,
    ));
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Utilise le catchupDays du stream sélectionné en priorité, sinon le paramètre global
    final maxDays = _selectedStream?.catchupDays ?? widget.catchupDays ?? 7;
    final hasXmltv = widget.tvgId != null;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Titre
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.replay_circle_filled,
                      color: kAetherSecondaryCyan, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Choisir un moment à revoir',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 20),

            // ---- Sélecteur de qualité (si plusieurs flux disponibles) ----
            if (widget.streams.length > 1) ...[
              _sectionLabel(context, 'Qualité', Icons.hd_outlined),
              const SizedBox(height: 10),
              _ChipRow<int>(
                items: List.generate(widget.streams.length, (i) => i),
                selected: _selectedStreamIndex,
                label: (i) => widget.streams[i].label,
                onSelected: (i) => setState(() => _selectedStreamIndex = i),
              ),
              const SizedBox(height: 20),
            ],

            // ---- Sélecteur de jour (partagé) ----
            _sectionLabel(context, 'Jour', Icons.calendar_today_outlined),
            const SizedBox(height: 10),
            _DaySelector(
              maxDays: maxDays,
              selected: _selectedDay,
              daysWithData: _daysWithData,
              onChanged: _onDayChanged,
            ),
            const SizedBox(height: 20),

            // ---- Grille XMLTV ----
            if (hasXmltv) ...[
              _sectionLabel(context, 'Programmes', Icons.tv_outlined),
              const SizedBox(height: 10),
              _XmltvProgramList(
                programs: _xmltvPrograms,
                isLoading: _isLoadingXmltv,
                onProgramSelected: _confirmFromXmltv,
              ),
              const SizedBox(height: 20),
              // Séparation avec le picker manuel
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'OU CHOISIR MANUELLEMENT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.35),
                      ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 20),
            ],

            // ---- Sélecteur d'heure ----
            _sectionLabel(context, 'Heure de début', Icons.schedule_outlined),
            const SizedBox(height: 10),
            _TimeSelector(
              time: _selectedTime,
              onChanged: (t) => setState(() => _selectedTime = t),
              isDark: isDark,
            ),
            const SizedBox(height: 20),

            // ---- Sélecteur de durée ----
            _sectionLabel(context, 'Durée', Icons.timelapse_outlined),
            const SizedBox(height: 10),
            _ChipRow<int>(
              items: _durations,
              selected: _durationMinutes,
              label: (d) => d < 60
                  ? '${d}min'
                  : (d % 60 == 0 ? '${d ~/ 60}h' : '${d ~/ 60}h${(d % 60).toString().padLeft(2, '0')}'),
              onSelected: (d) => setState(() => _durationMinutes = d),
            ),
            const SizedBox(height: 28),

            // ---- Bouton Regarder ----
            SizedBox(
              width: double.infinity,
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: kAetherGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _confirm,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.play_arrow_rounded,
                            color: kWhite, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'Regarder  •  ${_buildLabel()}',
                          style: const TextStyle(
                            color: kWhite,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Helpers ----

  Widget _sectionLabel(BuildContext ctx, String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: kAetherSecondaryCyan),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: kAetherSecondaryCyan,
          ),
        ),
      ],
    );
  }

  String _buildLabel() {
    final dayFmt = DateFormat('EEE d MMM', 'fr_FR').format(_selectedDay);
    final timeFmt = _selectedTime.format(context);
    final dur = _durationMinutes < 60
        ? '${_durationMinutes}min'
        : (_durationMinutes % 60 == 0
            ? '${_durationMinutes ~/ 60}h'
            : '${_durationMinutes ~/ 60}h${(_durationMinutes % 60).toString().padLeft(2, '0')}');
    return '$dayFmt à $timeFmt ($dur)';
  }

  void _confirm() {
    var start = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    // Si l'heure choisie est dans le futur, on ramène à 5min avant maintenant.
    final now = DateTime.now();
    if (start.isAfter(now)) {
      start = now.subtract(const Duration(minutes: 5));
    }
    final end = start.add(Duration(minutes: _durationMinutes));
    final label = _buildLabel();
    final stream = _selectedStream;
    Navigator.of(context).pop(ReplayProgram(
      title: 'Replay — $label',
      start: start,
      end: end,
      description: '',
      hasArchive: true,
      selectedStreamId: stream?.streamId,
      selectedStreamUrl: stream?.streamUrl,
      selectedCatchupSource: stream?.catchupSource,
    ));
  }
}

// ============================================================================
// Grille XMLTV
// ============================================================================

/// Liste des programmes XMLTV pour le jour sélectionné.
/// Chaque programme passé ou en cours est cliquable → lance le replay.
class _XmltvProgramList extends StatelessWidget {
  final List<XmltvProgram> programs;
  final bool isLoading;
  final void Function(XmltvProgram) onProgramSelected;

  const _XmltvProgramList({
    required this.programs,
    required this.isLoading,
    required this.onProgramSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        height: 56,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (programs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(Icons.info_outline,
                size: 16,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.35)),
            const SizedBox(width: 8),
            Text(
              'Aucune donnée EPG disponible',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.4),
              ),
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();
    return Column(
      children: programs.map((p) {
        final isNow = p.start.isBefore(now) && p.stop.isAfter(now);
        final isFuture = p.start.isAfter(now);
        return _XmltvProgramRow(
          program: p,
          isNow: isNow,
          isPlayable: !isFuture,
          onTap: isFuture ? null : () => onProgramSelected(p),
        );
      }).toList(),
    );
  }
}

/// Ligne d'un programme dans la grille XMLTV.
class _XmltvProgramRow extends StatelessWidget {
  final XmltvProgram program;
  final bool isNow;
  final bool isPlayable;
  final VoidCallback? onTap;

  const _XmltvProgramRow({
    required this.program,
    required this.isNow,
    required this.isPlayable,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final timeFmt = DateFormat('HH:mm');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: isNow
              ? kAetherPrimaryPurple.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isNow
              ? Border.all(
                  color: kAetherPrimaryPurple.withOpacity(0.35), width: 1)
              : null,
        ),
        child: Row(
          children: [
            // Colonne heure + durée
            SizedBox(
              width: 44,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    timeFmt.format(program.start),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isPlayable
                          ? onSurface
                          : onSurface.withOpacity(0.35),
                    ),
                  ),
                  Text(
                    program.durationLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: isPlayable
                          ? onSurface.withOpacity(0.5)
                          : onSurface.withOpacity(0.25),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Titre + badge EN COURS + catégorie
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isNow) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: kAetherVibrantMagenta.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '● EN COURS',
                            style: TextStyle(
                              color: kWhite,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          program.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                isNow ? FontWeight.bold : FontWeight.normal,
                            color: isPlayable
                                ? onSurface
                                : onSurface.withOpacity(0.35),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (program.category != null)
                    Text(
                      program.category!,
                      style: TextStyle(
                        fontSize: 11,
                        color: isPlayable
                            ? onSurface.withOpacity(0.45)
                            : onSurface.withOpacity(0.2),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Icône lecture (programmes jouables uniquement)
            if (isPlayable)
              Icon(
                Icons.play_circle_outline_rounded,
                size: 22,
                color: isNow
                    ? kAetherSecondaryCyan
                    : onSurface.withOpacity(0.4),
              )
            else
              const SizedBox(width: 22),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Widgets internes (picker manuel)
// ============================================================================

/// Sélecteur de jours sous forme de chips scrollables.
/// [daysWithData] : jours pour lesquels des données XMLTV existent — affiche un ● cyan.
class _DaySelector extends StatelessWidget {
  final int maxDays;
  final DateTime selected;
  final Set<DateTime> daysWithData;
  final ValueChanged<DateTime> onChanged;

  const _DaySelector({
    required this.maxDays,
    required this.selected,
    required this.onChanged,
    this.daysWithData = const {},
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List.generate(maxDays, (i) {
      final d = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: i));
      return d;
    });

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: days.map((d) {
          final isSelected = d.day == selected.day &&
              d.month == selected.month &&
              d.year == selected.year;
          final isToday = d.day == today.day && d.month == today.month;
          final isYesterday = d.day == today.day - 1 &&
              d.month == today.month;
          final hasEpg = daysWithData.contains(d);

          String label;
          if (isToday) {
            label = "Aujourd'hui";
          } else if (isYesterday) {
            label = 'Hier';
          } else {
            label = DateFormat('EEE d', 'fr_FR').format(d);
          }

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ChoiceChip(
                  label: Text(label),
                  selected: isSelected,
                  onSelected: (_) => onChanged(d),
                  selectedColor: kAetherPrimaryPurple,
                  labelStyle: TextStyle(
                    color: isSelected ? kWhite : null,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                // Indicateur EPG disponible
                const SizedBox(height: 3),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasEpg
                        ? kAetherSecondaryCyan
                        : Colors.transparent,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Sélecteur d'heure : bouton central avec flèches −15/+15 min.
class _TimeSelector extends StatelessWidget {
  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onChanged;
  final bool isDark;

  const _TimeSelector({
    required this.time,
    required this.onChanged,
    required this.isDark,
  });

  void _shift(int minutes) {
    final total = time.hour * 60 + time.minute + minutes;
    // Clamp entre minuit et maintenant (ne pas permettre de choisir le futur)
    final clamped = total.clamp(0, 23 * 60 + 45);
    onChanged(TimeOfDay(
      hour: clamped ~/ 60,
      minute: (clamped % 60).round(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? kContainerDark : kLightGrey;
    final label =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Row(
      children: [
        // ← -15min
        _ArrowButton(
          icon: Icons.remove,
          onTap: () => _shift(-15),
        ),
        const SizedBox(width: 8),
        // Heure (tap → showTimePicker)
        Expanded(
          child: GestureDetector(
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: time,
                builder: (ctx, child) => MediaQuery(
                  data: MediaQuery.of(ctx)
                      .copyWith(alwaysUse24HourFormat: true),
                  child: child!,
                ),
              );
              if (picked != null) onChanged(picked);
            },
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: kAetherPrimaryPurple.withOpacity(0.6), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.edit_outlined,
                      size: 16, color: kMediumGrey),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // +15min →
        _ArrowButton(
          icon: Icons.add,
          onTap: () => _shift(15),
        ),
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ArrowButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kAetherPrimaryPurple.withOpacity(0.15),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 52,
          child: Icon(icon, color: kAetherPrimaryPurple, size: 22),
        ),
      ),
    );
  }
}

/// Ligne de chips générique pour la sélection d'une valeur.
class _ChipRow<T> extends StatelessWidget {
  final List<T> items;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  const _ChipRow({
    required this.items,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        final isSelected = item == selected;
        return ChoiceChip(
          label: Text(label(item)),
          selected: isSelected,
          onSelected: (_) => onSelected(item),
          selectedColor: kAetherPrimaryPurple,
          labelStyle: TextStyle(
            color: isSelected ? kWhite : null,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        );
      }).toList(),
    );
  }
}
