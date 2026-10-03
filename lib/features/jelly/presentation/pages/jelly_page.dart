import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme.dart';
import '../../../../core/di/injection.dart';
import '../cubits/jelly_controls_cubit.dart';
import '../cubits/jelly_stats_cubit.dart';
import '../widgets/inside_experiment.dart';
import '../widgets/jelly_header.dart';
import '../widgets/jelly_viewport.dart';
import '../widgets/mobile_controls_sheet.dart';
import '../widgets/specimen_panel.dart';
import '../widgets/stats_bar.dart';

//* --- [ Jelly Page ] ---

class JellyPage extends StatelessWidget {
  const JellyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => getIt<JellyControlsCubit>()),
        BlocProvider(create: (_) => getIt<JellyStatsCubit>()),
      ],
      child: const JellyView(),
    );
  }
}

//// - ====================================================================== -

//* --- [ Jelly View ] ---

/// Landscape / tablet → side panel like the reference.
/// Portrait phone → stacked header + collapsible bottom controls sheet.
class JellyView extends StatelessWidget {
  const JellyView({super.key});

  static bool isWide(Size s) =>
      s.width >= 760 || (s.width > s.height && s.width >= 560);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JellyColors.background,
      body: LayoutBuilder(
        builder: (context, box) =>
            isWide(box.biggest) ? const _WideLayout() : const _CompactLayout(),
      ),
    );
  }
}

//// - ====================================================================== -

//* --- [ Wide Layout ] ---

class _WideLayout extends StatelessWidget {
  const _WideLayout();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          final margin = (w * 0.025).clamp(16.0, 28.0);
          final panelW = (w * 0.21).clamp(200.0, 250.0);
          final roomy = h >= 470;

          return Stack(
            children: [
              Positioned.fill(
                child: JellyViewport(
                  fill: 0.68,
                  focusInsets: EdgeInsets.only(
                    left: w * 0.1,
                    right: panelW + margin * 2,
                    top: h * 0.08,
                    bottom: h * 0.12,
                  ),
                ),
              ),
              Positioned(
                left: margin,
                top: margin,
                width: (w * 0.3).clamp(220.0, 360.0),
                child: _WideHeader(
                  titleSize: (h * 0.135).clamp(40.0, 96.0),
                  roomy: roomy,
                ),
              ),
              Positioned(
                left: margin,
                bottom: margin * 0.8,
                width: (w * 0.31).clamp(240.0, 330.0),
                child: _WideFooter(roomy: roomy),
              ),
              Positioned(
                top: margin,
                right: margin,
                bottom: margin * 0.8,
                width: panelW + 16,
                child: _SidePanel(panelWidth: panelW, dense: h < 640),
              ),
            ],
          );
        },
      ),
    );
  }
}

//* ---[ Wide header ]---

class _WideHeader extends StatelessWidget {
  const _WideHeader({required this.titleSize, required this.roomy});

  final double titleSize;
  final bool roomy;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StudyLabel(),
          SizedBox(height: roomy ? 18 : 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: JellyTitle(size: titleSize),
          ),
          if (roomy) ...[const SizedBox(height: 16), const JellyTagline()],
        ],
      ),
    );
  }
}

//* ---[ Wide footer ]---

class _WideFooter extends StatelessWidget {
  const _WideFooter({required this.roomy});

  final bool roomy;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const ToolHint(),
          const SizedBox(height: 14),
          StatsBar(showFootnote: roomy),
        ],
      ),
    );
  }
}

//* ---[ Side panel ]---

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.panelWidth, required this.dense});

  final double panelWidth;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const StatusChip(),
        const SizedBox(height: 12),
        Expanded(
          child: Align(
            alignment: Alignment.topRight,
            child: Container(
              width: panelWidth,
              decoration: BoxDecoration(
                color: JellyColors.panel.withValues(alpha: 0.86),
                border: Border.all(color: JellyColors.line),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: SpecimenPanel(dense: dense),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const InsideExperiment(),
      ],
    );
  }
}

//// - ====================================================================== -

//* --- [ Compact Layout ] ---

class _CompactLayout extends StatelessWidget {
  const _CompactLayout();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          return Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CompactHeader(titleSize: (w * 0.15).clamp(44.0, 76.0)),
                  const Expanded(child: _CompactViewport()),
                  _CompactFooter(roomy: h >= 720),
                  SizedBox(
                    height:
                        MobileControlsSheet.collapsedHeight + bottomInset + 12,
                  ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: MobileControlsSheet(
                  maxExpandedHeight: h * _CompactViewport.sheetFraction,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

//* ---[ Compact viewport ]---

/// Re-centres the specimen above the sheet while the controls are expanded.
class _CompactViewport extends StatelessWidget {
  const _CompactViewport();

  /// Max share of the screen height the expanded sheet may take.
  static const double sheetFraction = 0.46;

  @override
  Widget build(BuildContext context) {
    final expanded = context.select<JellyControlsCubit, bool>(
      (c) => c.state.panelExpanded,
    );
    return LayoutBuilder(
      builder: (context, box) => JellyViewport(
        fill: 0.84,
        focusInsets: EdgeInsets.only(
          top: 8,
          bottom: expanded ? box.maxHeight * 0.55 : 8,
        ),
      ),
    );
  }
}

//* ---[ Compact header ]---

class _CompactHeader extends StatelessWidget {
  const _CompactHeader({required this.titleSize});

  final double titleSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Expanded(child: StudyLabel()),
              StatusChip(),
            ],
          ),
          const SizedBox(height: 14),
          IgnorePointer(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  flex: 3,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomLeft,
                    child: JellyTitle(size: titleSize),
                  ),
                ),
                const SizedBox(width: 18),
                const Flexible(
                  flex: 2,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.bottomLeft,
                      child: JellyTagline(size: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

//* ---[ Compact footer ]---

class _CompactFooter extends StatelessWidget {
  const _CompactFooter({required this.roomy});

  final bool roomy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: IgnorePointer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ToolHint(compact: true),
            const SizedBox(height: 10),
            StatsBar(showFootnote: roomy),
          ],
        ),
      ),
    );
  }
}
