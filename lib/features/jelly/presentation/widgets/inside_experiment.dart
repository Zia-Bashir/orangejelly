import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme.dart';
import '../../physics/jelly_engine.dart';
import '../cubits/jelly_controls_cubit.dart';
import '../cubits/jelly_stats_cubit.dart';

//* --- [ Inside The Experiment ] ---

/// Collapsible footer explaining how the specimen is simulated.
class InsideExperiment extends StatelessWidget {
  const InsideExperiment({super.key, this.bordered = true});

  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final expanded = context.select<JellyControlsCubit, bool>(
      (c) => c.state.insideExpanded,
    );
    return Container(
      decoration: bordered
          ? BoxDecoration(
              color: JellyColors.panel,
              border: Border.all(color: JellyColors.line),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: context.read<JellyControlsCubit>().toggleInside,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'INSIDE THE EXPERIMENT',
                      style: JellyText.label,
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.125 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.add,
                      size: 14,
                      color: JellyColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded ? const _Body() : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

//// - ====================================================================== -

//* --- [ Body ] ---

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<JellyStatsCubit, JellyStats>(
      buildWhen: (a, b) =>
          a.particles != b.particles || a.tetrahedra != b.tetrahedra,
      builder: (context, s) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Text(
            'The orange slice is ${s.tetrahedra} tetrahedra hung on ${s.particles} '
            'particles, solved with extended position-based dynamics (XPBD) '
            'in small substeps every frame. Edge constraints give it '
            'firmness; per-tetrahedron volume constraints keep it from '
            'deflating. The knife splits tetrahedra along the swipe plane and '
            'duplicates shared particles, so every connected component '
            'becomes an independent soft body. Shading is computed per vertex '
            'on the CPU and drawn with Canvas.drawVertices.',
            style: JellyText.serifItalic.copyWith(
              fontSize: 13,
              color: JellyColors.inkSoft,
            ),
          ),
        );
      },
    );
  }
}
