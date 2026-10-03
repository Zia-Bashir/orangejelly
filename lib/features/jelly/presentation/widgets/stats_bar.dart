import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme.dart';
import '../../physics/jelly_engine.dart';
import '../cubits/jelly_stats_cubit.dart';
import 'control_primitives.dart';

//* --- [ Stats Bar ] ---

/// MASS · VOLUME · KINETIC · PIECES readouts with hairline separators.
class StatsBar extends StatelessWidget {
  const StatsBar({super.key, this.showFootnote = true});

  final bool showFootnote;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<JellyStatsCubit, JellyStats>(
      builder: (context, s) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Hairline(),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Stat(
                    first: true,
                    label: 'Mass',
                    value: '≈${s.massGrams.toStringAsFixed(0)}',
                    unit: 'g',
                  ),
                  const Hairline(vertical: true),
                  _Stat(
                    flex: 14,
                    label: 'Volume',
                    value: s.volumePercent.toStringAsFixed(1),
                    unit: '% of rest',
                  ),
                  const Hairline(vertical: true),
                  _Stat(
                    flex: 11,
                    label: 'Kinetic',
                    value: _kinetic(s.kineticMicroJoules),
                    unit: 'µJ',
                  ),
                  const Hairline(vertical: true),
                  _Stat(
                    flex: 8,
                    label: 'Pieces',
                    value: '${s.pieces}',
                    unit: '',
                  ),
                ],
              ),
            ),
            const Hairline(),
            if (showFootnote) ...[
              const SizedBox(height: 8),
              const Text(
                'Illustrative scale: 1 sim unit = 3.5 cm, gummy at 1.3 g/cm³. '
                'Volume and energy are summed live over every tetrahedron '
                'and particle.',
                style: JellyText.small,
              ),
            ],
          ],
        );
      },
    );
  }

  static String _kinetic(double v) {
    if (v >= 1000) return v.toStringAsFixed(0);
    if (v >= 100) return v.toStringAsFixed(1);
    return v.toStringAsFixed(2);
  }
}

//// - ====================================================================== -

//* --- [ Stat Cell ] ---

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.unit,
    this.first = false,
    this.flex = 9,
  });

  final bool first;
  final int flex;
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: EdgeInsets.fromLTRB(first ? 0 : 10, 9, 6, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(), style: JellyText.label),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: value, style: JellyText.statValue),
                    if (unit.isNotEmpty)
                      TextSpan(text: ' $unit', style: JellyText.statUnit),
                  ],
                ),
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
