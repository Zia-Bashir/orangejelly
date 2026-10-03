import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../render/jelly_palette.dart';

//* --- [ Section Label ] ---

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(text.toUpperCase(), style: JellyText.label)),
        ?trailing,
      ],
    );
  }
}

//// - ====================================================================== -

//* --- [ Hairline ] ---

class Hairline extends StatelessWidget {
  const Hairline({super.key, this.vertical = false});

  final bool vertical;

  @override
  Widget build(BuildContext context) {
    return vertical
        ? const VerticalDivider(width: 1, thickness: 1, color: JellyColors.line)
        : const Divider(height: 1, thickness: 1, color: JellyColors.line);
  }
}

//// - ====================================================================== -

//* --- [ Tool Button ] ---

class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.height = 34,
  });

  final String label;
  final Widget Function(Color color) icon;
  final bool selected;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? JellyColors.background : JellyColors.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: height,
          decoration: BoxDecoration(
            color: selected ? JellyColors.ink : Colors.transparent,
            border: Border.all(
              color: selected ? JellyColors.ink : JellyColors.lineStrong,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon(fg),
              const SizedBox(width: 8),
              Text(label, style: JellyText.button.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

//// - ====================================================================== -

//* --- [ Tool Icons ] ---

Widget handIcon(Color color) =>
    Icon(Icons.back_hand_outlined, size: 13, color: color);

Widget knifeIcon(Color color) => SizedBox(
  width: 14,
  height: 14,
  child: CustomPaint(painter: _KnifeGlyph(color)),
);

class _KnifeGlyph extends CustomPainter {
  const _KnifeGlyph(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final blade = Path()
      ..moveTo(s * 0.95, s * 0.05)
      ..lineTo(s * 0.42, s * 0.50)
      ..lineTo(s * 0.52, s * 0.60)
      ..quadraticBezierTo(s * 0.92, s * 0.32, s * 0.95, s * 0.05)
      ..close();
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(blade, paint);
    canvas.drawLine(
      Offset(s * 0.44, s * 0.58),
      Offset(s * 0.10, s * 0.92),
      paint
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_KnifeGlyph old) => old.color != color;
}

//// - ====================================================================== -

//* --- [ Variety Swatch ] ---

class VarietySwatch extends StatelessWidget {
  const VarietySwatch({
    super.key,
    required this.variety,
    required this.selected,
    required this.onTap,
  });

  final JellyVariety variety;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = variety.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: variety.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(5, 5, 5, 4),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? JellyColors.lineStrong : Colors.transparent,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(height: 3, color: p.skinDark),
              Container(height: 3, color: p.cream),
              Container(height: 12, color: p.fleshDeep),
              const SizedBox(height: 5),
              Text(
                variety.label,
                textAlign: TextAlign.center,
                style: JellyText.caption.copyWith(
                  fontSize: 12,
                  color: selected ? JellyColors.ink : JellyColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//// - ====================================================================== -

//* --- [ Labeled Slider ] ---

class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.minLabel,
    required this.maxLabel,
    required this.onChanged,
  });

  final String label;
  final double value;
  final String minLabel;
  final String maxLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionLabel(
          label,
          trailing: Text(
            value.toStringAsFixed(2),
            style: JellyText.mono.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
        SizedBox(
          height: 28,
          child: Slider(value: value, onChanged: onChanged),
        ),
        Row(
          children: [
            Text(minLabel, style: JellyText.caption),
            const Spacer(),
            Text(maxLabel, style: JellyText.caption),
          ],
        ),
      ],
    );
  }
}

//// - ====================================================================== -

//* --- [ Outline Action Button ] ---

class OutlineActionButton extends StatelessWidget {
  const OutlineActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 34,
  });

  final String label;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: const Color(0x14161513),
        child: Container(
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: JellyColors.lineStrong),
          ),
          child: Text(label, style: JellyText.button),
        ),
      ),
    );
  }
}

//// - ====================================================================== -

//* --- [ Tiny Checkbox ] ---

class TinyCheckbox extends StatelessWidget {
  const TinyCheckbox({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: value,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: value ? JellyColors.ink : Colors.transparent,
                  border: Border.all(color: JellyColors.inkSoft),
                ),
                child: value
                    ? const Icon(
                        Icons.check,
                        size: 9,
                        color: JellyColors.background,
                      )
                    : null,
              ),
              const SizedBox(width: 7),
              Text(label, style: JellyText.button.copyWith(fontSize: 11.5)),
            ],
          ),
        ),
      ),
    );
  }
}
