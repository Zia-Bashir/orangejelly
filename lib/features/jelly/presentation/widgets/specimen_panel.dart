import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme.dart';
import '../../render/jelly_palette.dart';
import '../cubits/jelly_controls_cubit.dart';
import '../cubits/jelly_controls_state.dart';
import 'control_primitives.dart';

//* --- [ Specimen Panel ] ---

/// "THE SPECIMEN" controls: tool, variety, firmness, damping and actions.
/// Shared by the wide side panel and the portrait bottom sheet.
class SpecimenPanel extends StatelessWidget {
  const SpecimenPanel({
    super.key,
    this.showHeader = true,
    this.showTool = true,
    this.dense = false,
  });

  final bool showHeader;
  final bool showTool;

  /// Tighter spacing + shorter controls for short landscape viewports.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<JellyControlsCubit>();
    final k = dense ? 0.4 : 1.0;
    final controlHeight = dense ? 28.0 : 34.0;
    Widget gap(double h) => SizedBox(height: h * k);
    return BlocBuilder<JellyControlsCubit, JellyControlsState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showHeader) ...[
              SectionLabel(
                'The Specimen',
                trailing: Text('fig. 9', style: JellyText.caption),
              ),
              gap(10),
              const Hairline(),
              gap(14),
            ],
            if (showTool) ...[
              const SectionLabel('Tool'),
              gap(8),
              ToolSelector(
                selected: state.tool,
                onSelect: cubit.selectTool,
                height: controlHeight,
              ),
              gap(18),
            ],
            const SectionLabel('Variety'),
            gap(8),
            Row(
              children: [
                for (final v in JellyVariety.values) ...[
                  Expanded(
                    child: VarietySwatch(
                      variety: v,
                      selected: state.variety == v,
                      onTap: () => cubit.selectVariety(v),
                    ),
                  ),
                  if (v != JellyVariety.values.last) const SizedBox(width: 8),
                ],
              ],
            ),
            gap(14),
            const Hairline(),
            gap(12),
            LabeledSlider(
              label: 'Firmness',
              value: state.firmness,
              minLabel: 'trembling',
              maxLabel: 'set',
              onChanged: cubit.setFirmness,
            ),
            gap(6),
            LabeledSlider(
              label: 'Internal damping',
              value: state.damping,
              minLabel: 'lively',
              maxLabel: 'syrupy',
              onChanged: cubit.setDamping,
            ),
            gap(14),
            const Hairline(),
            gap(14),
            Row(
              children: [
                Expanded(
                  flex: 7,
                  child: OutlineActionButton(
                    label: 'Give it a nudge',
                    height: controlHeight,
                    onTap: cubit.nudge,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 3,
                  child: OutlineActionButton(
                    label: 'Reset',
                    height: controlHeight,
                    onTap: cubit.reset,
                  ),
                ),
              ],
            ),
            gap(6),
            Wrap(
              spacing: 16,
              children: [
                TinyCheckbox(
                  label: '¼ speed',
                  value: state.quarterSpeed,
                  onTap: cubit.toggleQuarterSpeed,
                ),
                TinyCheckbox(
                  label: 'Show mesh',
                  value: state.showMesh,
                  onTap: cubit.toggleShowMesh,
                ),
              ],
            ),
            gap(6),
            OutlineActionButton(
              label: state.paused ? 'Resume' : 'Pause',
              height: controlHeight,
              onTap: cubit.togglePaused,
            ),
          ],
        );
      },
    );
  }
}

//// - ====================================================================== -

//* --- [ Tool Selector ] ---

class ToolSelector extends StatelessWidget {
  const ToolSelector({
    super.key,
    required this.selected,
    required this.onSelect,
    this.height = 34,
  });

  final JellyTool selected;
  final ValueChanged<JellyTool> onSelect;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ToolButton(
            label: JellyTool.hand.label,
            icon: handIcon,
            height: height,
            selected: selected == JellyTool.hand,
            onTap: () => onSelect(JellyTool.hand),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: ToolButton(
            label: JellyTool.knife.label,
            icon: knifeIcon,
            height: height,
            selected: selected == JellyTool.knife,
            onTap: () => onSelect(JellyTool.knife),
          ),
        ),
      ],
    );
  }
}
