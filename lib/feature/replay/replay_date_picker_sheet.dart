import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/themes/colors.dart';
import '../../data/services/replay_service.dart';

/// Sheet permettant à l'utilisateur de choisir manuellement
/// un jour, une heure et une durée pour lancer un replay.
///
/// Retourne un [ReplayProgram] synthétique (title = label affiché dans le player).
/// Ce widget est conçu pour être remplacé plus tard par une vraie grille EPG.
class ReplayDatePickerSheet extends StatefulWidget {
  final int? catchupDays;

  const ReplayDatePickerSheet({super.key, this.catchupDays});

  @override
  State<ReplayDatePickerSheet> createState() => _ReplayDatePickerSheetState();
}

class _ReplayDatePickerSheetState extends State<ReplayDatePickerSheet> {
  // ---- Sélections ----
  late DateTime _selectedDay;   // minuit du jour choisi
  late TimeOfDay _selectedTime; // heure de début
  int _durationMinutes = 60;    // durée sélectionnée

  static const _durations = [30, 60, 90, 120, 180];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Par défaut : hier, heure actuelle arrondie à la demi-heure précédente
    _selectedDay = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    final roundedMinute = now.minute >= 30 ? 30 : 0;
    _selectedTime = TimeOfDay(hour: now.hour, minute: roundedMinute);
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxDays = widget.catchupDays ?? 7;

    return SafeArea(
      child: Padding(
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

            // ---- Sélecteur de jour ----
            _sectionLabel(context, 'Jour', Icons.calendar_today_outlined),
            const SizedBox(height: 10),
            _DaySelector(
              maxDays: maxDays,
              selected: _selectedDay,
              onChanged: (d) => setState(() => _selectedDay = d),
            ),
            const SizedBox(height: 20),

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
    final start = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    final end = start.add(Duration(minutes: _durationMinutes));
    final label = _buildLabel();
    Navigator.of(context).pop(ReplayProgram(
      title: 'Replay — $label',
      start: start,
      end: end,
      description: '',
      hasArchive: true,
    ));
  }
}

// ============================================================================
// Widgets internes
// ============================================================================

/// Sélecteur de jours sous forme de chips scrollables.
class _DaySelector extends StatelessWidget {
  final int maxDays;
  final DateTime selected;
  final ValueChanged<DateTime> onChanged;

  const _DaySelector({
    required this.maxDays,
    required this.selected,
    required this.onChanged,
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
            child: ChoiceChip(
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
