import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../physics/jelly_engine.dart';
import '../../render/jelly_camera.dart';
import '../../render/jelly_painter.dart';
import '../../render/jelly_renderer.dart';
import '../../render/knife_renderer.dart';
import '../cubits/jelly_controls_cubit.dart';
import '../cubits/jelly_controls_state.dart';
import '../cubits/jelly_stats_cubit.dart';
import '../cubits/knife_cubit.dart';

//* --- [ Jelly Viewport ] ---

/// Hosts the simulation loop and the 3D canvas.
///
/// The [AnimationController] is only the frame clock (created/disposed here)
/// and doubles as the painter's repaint listenable. All UI state lives in
/// [JellyControlsCubit] / [JellyStatsCubit] / [KnifeCubit]; pointer
/// bookkeeping is gesture plumbing held in [_PointerSession].
class JellyViewport extends StatefulWidget {
  const JellyViewport({
    super.key,
    this.fill = 0.72,
    this.focusInsets = EdgeInsets.zero,
  });

  final double fill;
  final EdgeInsets focusInsets;

  @override
  State<JellyViewport> createState() => _JellyViewportState();
}

class _JellyViewportState extends State<JellyViewport>
    with SingleTickerProviderStateMixin {
  late final AnimationController _frames;
  final JellyEngine _engine = getIt<JellyEngine>();
  final JellyCamera _camera = JellyCamera();
  final JellyRenderer _renderer = JellyRenderer();
  final KnifeRenderer _knifeRenderer = KnifeRenderer();
  final _PointerSession _session = _PointerSession();

  Duration _lastElapsed = Duration.zero;
  double _statsTimer = 0;

  static const double _statsInterval = 0.1;

  //* --- [ Lifecycle ] ---

  @override
  void initState() {
    super.initState();
    _frames =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..addListener(_onFrame)
          ..repeat();
  }

  @override
  void dispose() {
    _engine.endGrab();
    _frames
      ..removeListener(_onFrame)
      ..dispose();
    super.dispose();
  }

  //* --- [ Frame Loop ] ---

  void _onFrame() {
    final elapsed = _frames.lastElapsedDuration ?? Duration.zero;
    final dt = math.min((elapsed - _lastElapsed).inMicroseconds / 1e6, 1 / 20);
    _lastElapsed = elapsed;
    if (dt <= 0) return;

    final controls = context.read<JellyControlsCubit>().state;
    if (!controls.paused) _engine.advance(dt * controls.timeScale);
    final cut = context.read<KnifeCubit>().tick(dt);

    _statsTimer += dt;
    if (_statsTimer >= _statsInterval || (cut?.didCut ?? false)) {
      _statsTimer = 0;
      context.read<JellyStatsCubit>().refresh();
    }
  }

  //* --- [ Pointer Handling ] ---

  JellyTool get _tool => context.read<JellyControlsCubit>().state.tool;
  KnifeCubit get _knife => context.read<KnifeCubit>();

  void _onPointerDown(PointerDownEvent e) {
    final p = e.localPosition;
    _session.positions[e.pointer] = p;
    switch (_tool) {
      case JellyTool.hand:
        if (_session.grabPointer == null) {
          if (_engine.beginGrab(_camera, p.dx, p.dy)) {
            _session.grabPointer = e.pointer;
          }
        } else if (_session.twistPointer == null) {
          _session.twistPointer = e.pointer;
          _session.twistAngle = _session.currentTwistAngle();
        }
      case JellyTool.knife:
        if (_session.knifePointer == null && _knife.beginAim(_camera, p)) {
          _session.knifePointer = e.pointer;
        }
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    final p = e.localPosition;
    _session.positions[e.pointer] = p;
    if (e.pointer == _session.knifePointer) {
      _knife.updateAim(_camera, p);
      return;
    }
    if (_session.grabPointer == null) return;
    if (e.pointer == _session.grabPointer) {
      _engine.moveGrab(_camera, p.dx, p.dy);
    }
    if (_session.twistPointer != null &&
        (e.pointer == _session.grabPointer ||
            e.pointer == _session.twistPointer)) {
      final angle = _session.currentTwistAngle();
      var delta = angle - _session.twistAngle;
      if (delta > math.pi) delta -= 2 * math.pi;
      if (delta < -math.pi) delta += 2 * math.pi;
      _session.twistAngle = angle;
      _engine.twistGrab(delta);
    }
  }

  void _onPointerUp(PointerEvent e) {
    _session.positions.remove(e.pointer);
    if (e.pointer == _session.knifePointer) {
      _session.knifePointer = null;
      _knife.release(_camera);
      return;
    }
    if (e.pointer == _session.grabPointer) {
      _engine.endGrab();
      _session
        ..grabPointer = null
        ..twistPointer = null;
    } else if (e.pointer == _session.twistPointer) {
      _session.twistPointer = null;
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (e.pointer == _session.knifePointer) {
      _session.knifePointer = null;
      _session.positions.remove(e.pointer);
      _knife.cancel();
      return;
    }
    _onPointerUp(e);
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent && _engine.isGrabbing) {
      _engine.twistGrab(e.scrollDelta.dy * 0.004);
    }
  }

  //* --- [ Build ] ---

  @override
  Widget build(BuildContext context) {
    return BlocListener<JellyControlsCubit, JellyControlsState>(
      listenWhen: (a, b) => a.tool != b.tool,
      listener: (context, state) {
        _session.knifePointer = null;
        context.read<KnifeCubit>().cancel();
      },
      child: BlocBuilder<JellyControlsCubit, JellyControlsState>(
        buildWhen: (a, b) => a.variety != b.variety || a.showMesh != b.showMesh,
        builder: (context, state) {
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            onPointerSignal: _onPointerSignal,
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: JellyPainter(
                  engine: _engine,
                  camera: _camera,
                  renderer: _renderer,
                  knifeRenderer: _knifeRenderer,
                  knife: context.read<KnifeCubit>(),
                  palette: state.variety.palette,
                  showMesh: state.showMesh,
                  fill: widget.fill,
                  focusInsets: widget.focusInsets,
                  repaint: _frames,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

//// - ====================================================================== -

//* --- [ Pointer Session ] ---

/// Raw multi-touch bookkeeping: which pointer grabs, which twists, which
/// slices. Not UI state — nothing rebuilds from it.
class _PointerSession {
  final Map<int, Offset> positions = <int, Offset>{};
  int? grabPointer;
  int? twistPointer;
  int? knifePointer;
  double twistAngle = 0;

  double currentTwistAngle() {
    final a = positions[grabPointer];
    final b = positions[twistPointer];
    if (a == null || b == null) return twistAngle;
    return math.atan2(b.dy - a.dy, b.dx - a.dx);
  }
}
