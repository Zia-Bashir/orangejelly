import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme.dart';
import '../cubits/jelly_controls_cubit.dart';
import '../cubits/jelly_controls_state.dart';

//* --- [ Study Label ] ---

class StudyLabel extends StatelessWidget {
  const StudyLabel({super.key});

  @override
  Widget build(BuildContext context) =>
      const Text('MATERIAL STUDIES / NO. 010', style: JellyText.label);
}

//// - ====================================================================== -

//* --- [ Jelly Title ] ---

/// "Orange / Jelly." with the second line indented like the reference.
class JellyTitle extends StatelessWidget {
  const JellyTitle({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final style = JellyText.title(size);
    return Semantics(
      header: true,
      label: 'Orange Jelly.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Orange', style: style),
            Padding(
              padding: EdgeInsets.only(left: size * 0.42),
              child: Text('Jelly.', style: style),
            ),
          ],
        ),
      ),
    );
  }
}

//// - ====================================================================== -

//* --- [ Tagline ] ---

class JellyTagline extends StatelessWidget {
  const JellyTagline({super.key, this.size = 15.5});

  final double size;

  @override
  Widget build(BuildContext context) => Text(
    'A wedge of sunshine.\nA little wobble.\nToo soft to share.',
    style: JellyText.tagline.copyWith(fontSize: size),
  );
}

//// - ====================================================================== -

//* --- [ Status Chip ] ---

class StatusChip extends StatelessWidget {
  const StatusChip({super.key});

  @override
  Widget build(BuildContext context) {
    final paused = context.select<JellyControlsCubit, bool>(
      (c) => c.state.paused,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: JellyColors.panel,
        border: Border.all(color: JellyColors.line),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: paused ? JellyColors.paused : JellyColors.live,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            paused ? 'CANVAS · PAUSED' : 'CANVAS · LIVE',
            style: JellyText.mono.copyWith(fontSize: 9.5, letterSpacing: 1.2),
          ),
        ],
      ),
    );
  }
}

//// - ====================================================================== -

//* --- [ Tool Hint ] ---

class ToolHint extends StatelessWidget {
  const ToolHint({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tool = context.select<JellyControlsCubit, JellyTool>(
      (c) => c.state.tool,
    );
    final text = switch (tool) {
      JellyTool.hand =>
        compact
            ? 'Grab any piece — tip, corner, flesh or peel — and pull. '
                  'Add a second finger while holding to twist it.'
            : 'Grab any piece — tip, corner, flesh or peel — and pull. '
                  'Scroll, or add a second finger, while holding to twist it.',
      JellyTool.knife =>
        'Draw a line across the slice — the knife lines up over it and '
            'cuts when you let go. Cut the pieces again, as small as you '
            'like.',
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Text.rich(
        key: ValueKey(tool),
        TextSpan(
          children: [
            TextSpan(
              text: '${tool.label.toUpperCase()}  ',
              style: JellyText.label,
            ),
            TextSpan(text: text, style: JellyText.serifItalic),
          ],
        ),
      ),
    );
  }
}
