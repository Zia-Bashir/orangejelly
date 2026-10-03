import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme.dart';
import '../cubits/jelly_controls_cubit.dart';
import '../cubits/jelly_controls_state.dart';
import 'control_primitives.dart';
import 'inside_experiment.dart';
import 'specimen_panel.dart';

//* --- [ Mobile Controls Sheet ] ---

/// Portrait bottom sheet: the tool switch stays in reach while collapsed;
/// expanding reveals the full specimen panel.
class MobileControlsSheet extends StatelessWidget {
  const MobileControlsSheet({super.key, required this.maxExpandedHeight});

  /// Height of the always-visible bar (excluding the bottom safe area).
  static const double collapsedHeight = 62;

  final double maxExpandedHeight;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<JellyControlsCubit>();
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return BlocBuilder<JellyControlsCubit, JellyControlsState>(
      buildWhen: (a, b) =>
          a.panelExpanded != b.panelExpanded || a.tool != b.tool,
      builder: (context, state) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: JellyColors.panel,
            border: Border(top: BorderSide(color: JellyColors.line)),
            boxShadow: [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 18,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: collapsedHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: ToolSelector(
                            selected: state.tool,
                            onSelect: cubit.selectTool,
                            height: 38,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _ExpandButton(
                          expanded: state.panelExpanded,
                          onTap: cubit.togglePanel,
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: state.panelExpanded
                      ? ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: maxExpandedHeight,
                          ),
                          child: const SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Hairline(),
                                SizedBox(height: 12),
                                SpecimenPanel(showTool: false),
                                SizedBox(height: 14),
                                InsideExperiment(),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

//// - ====================================================================== -

//* --- [ Expand Button ] ---

class _ExpandButton extends StatelessWidget {
  const _ExpandButton({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: expanded ? 'Hide specimen controls' : 'Show specimen controls',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: JellyColors.lineStrong),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('SPECIMEN', style: JellyText.label),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                child: const Icon(
                  Icons.keyboard_arrow_up,
                  size: 16,
                  color: JellyColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
