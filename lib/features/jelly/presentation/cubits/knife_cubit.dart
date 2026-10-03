import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../physics/jelly_cutter.dart';
import '../../physics/jelly_engine.dart';
import '../../physics/slice_mesh.dart';
import '../../render/jelly_camera.dart';
import 'knife_state.dart';

//* --- [ Knife Cubit ] ---

/// Drives the knife tool: while the finger is down the blade hovers over the
/// drawn line (nothing is cut); on release it chops down, the cut fires on
/// the [JellyEngine] at impact, then the blade lifts away and fades.
///
/// The viewport forwards pointer events and calls [tick] once per frame.
@injectable
class KnifeCubit extends Cubit<KnifeState> {
  KnifeCubit(this._engine) : super(const KnifeState());

  final JellyEngine _engine;

  //* ---[ Tuning ]---

  /// Shortest drawn line (logical px) that triggers a chop.
  static const double minSwipePx = 24;

  /// World height the drawn line is mapped onto (the jelly's top surface).
  static const double linePlaneY = SliceGeometry.thickness * 0.95;

  /// Cutting-edge height while hovering.
  static const double hoverY = SliceGeometry.thickness + 0.7;

  /// Edge height at which the blade is mid-jelly and the cut executes.
  static const double impactY = SliceGeometry.thickness * 0.45;

  static const double chopSeconds = 0.20;
  static const double holdSeconds = 0.08;
  static const double liftSeconds = 0.45;
  static const double fadeInSeconds = 0.12;

  //* ---[ Session ]---

  final Float64List _hit = Float64List(3);
  Offset? _start;
  Offset? _end;
  double _targetX = 0, _targetZ = 0, _targetYaw = 0;
  double _ax = 0, _az = 0, _bx = 0, _bz = 0;

  /// Blade tip points screen-right (handle on the left) unless flipped.
  bool _flipped = false;
  double _phaseTime = 0;
  double _liftFrom = hoverY;
  double _clock = 0;
  bool _cutFired = false;

  bool get isBusy => state.phase == KnifePhase.chopping;

  //* --- [ Aiming ] ---

  /// Starts drawing a cut line at [p]. Ignored mid-chop (returns false).
  bool beginAim(JellyCamera cam, Offset p) {
    if (state.phase == KnifePhase.chopping) return false;
    _start = p;
    _end = p;
    _flipped = false;
    _cutFired = false;
    _phaseTime = 0;
    _retarget(cam, snap: true);
    debugPrint('✅ (APP LOGS) [knife] : aim -> $p');
    emit(
      KnifeState(
        phase: KnifePhase.aiming,
        guideStart: p,
        guideEnd: p,
        guideOpacity: 1,
        x: _targetX,
        z: _targetZ,
        yaw: _targetYaw,
        edgeY: hoverY,
        opacity: state.phase == KnifePhase.lifting ? state.opacity : 0,
      ),
    );
    return true;
  }

  /// Extends the drawn line to [p]; the hovering blade re-aligns over it.
  void updateAim(JellyCamera cam, Offset p) {
    if (state.phase != KnifePhase.aiming) return;
    _end = p;
    _retarget(cam);
    emit(_copy(guideEnd: p));
  }

  /// Finger lifted: chops if the line is long enough, else puts the knife
  /// away. Returns true when a chop started.
  bool release(JellyCamera cam) {
    if (state.phase != KnifePhase.aiming) return false;
    final a = _start, b = _end;
    if (a == null || b == null || (b - a).distance < minSwipePx) {
      debugPrint('✅ (APP LOGS) [knife] : release -> too short, no cut');
      _startLift();
      return false;
    }
    _retarget(cam);
    _phaseTime = 0;
    _cutFired = false;
    debugPrint('✅ (APP LOGS) [knife] : release -> chop');
    emit(_copy(phase: KnifePhase.chopping));
    return true;
  }

  /// Aborts the knife immediately (tool switch, pointer cancel).
  void cancel() {
    if (state.phase == KnifePhase.idle) return;
    _start = null;
    _end = null;
    debugPrint('✅ (APP LOGS) [knife] : cancel');
    emit(const KnifeState());
  }

  //* --- [ Frame Tick ] ---

  /// Advances the animation by [dt] real seconds. Returns the [CutResult]
  /// on the frame the blade reaches the jelly, otherwise null.
  CutResult? tick(double dt) {
    if (state.phase == KnifePhase.idle || dt <= 0) return null;
    _clock += dt;
    _phaseTime += dt;
    CutResult? result;

    switch (state.phase) {
      case KnifePhase.idle:
        return null;

      //* ---[ Hover over the line ]---

      case KnifePhase.aiming:
        final follow = 1 - math.exp(-dt * 20);
        emit(
          _copy(
            x: _lerp(state.x, _targetX, follow),
            z: _lerp(state.z, _targetZ, follow),
            yaw: state.yaw + _angleDelta(state.yaw, _targetYaw) * follow,
            edgeY: hoverY + 0.03 * math.sin(_clock * 4.5),
            opacity: math.min(1.0, state.opacity + dt / fadeInSeconds),
          ),
        );

      //* ---[ Chop down ]---

      case KnifePhase.chopping:
        final t = math.min(1.0, _phaseTime / chopSeconds);
        final align = math.min(1.0, t * 3);
        final edgeY = _lerp(hoverY, 0, t * t * t);
        if (!_cutFired && edgeY <= impactY) {
          _cutFired = true;
          result = _engine.sliceAlong(_ax, _az, _bx, _bz);
          debugPrint(
            '✅ (APP LOGS) [knife] : impact -> cut ${result.didCut}, '
            'pieces ${result.piecesAfter}',
          );
        }
        final hold = _phaseTime >= chopSeconds + holdSeconds;
        if (hold) _liftFrom = edgeY;
        emit(
          _copy(
            phase: hold ? KnifePhase.lifting : KnifePhase.chopping,
            x: _lerp(state.x, _targetX, align),
            z: _lerp(state.z, _targetZ, align),
            yaw: state.yaw + _angleDelta(state.yaw, _targetYaw) * align,
            edgeY: edgeY,
            opacity: 1,
            guideOpacity: 1 - t,
          ),
        );
        if (hold) _phaseTime = 0;

      //* ---[ Lift + fade ]---

      case KnifePhase.lifting:
        final t = math.min(1.0, _phaseTime / liftSeconds);
        final ease = 1 - (1 - t) * (1 - t);
        if (t >= 1) {
          _start = null;
          _end = null;
          emit(const KnifeState());
        } else {
          emit(
            _copy(
              edgeY: _lerp(_liftFrom, hoverY + 0.5, ease),
              opacity: math.min(state.opacity, 1 - _smooth(0.25, 1, t)),
              guideOpacity: math.max(0.0, state.guideOpacity - dt * 6),
            ),
          );
        }
    }
    return result;
  }

  //* --- [ Helpers ] ---

  void _startLift() {
    _phaseTime = 0;
    _liftFrom = state.edgeY;
    emit(_copy(phase: KnifePhase.lifting));
  }

  /// Maps the drawn screen line onto the jelly-top plane and derives the
  /// blade target pose (centred over the line, handle on the screen-left).
  void _retarget(JellyCamera cam, {bool snap = false}) {
    final a = _start, b = _end;
    if (a == null || b == null) return;
    cam.planePoint(a.dx, a.dy, linePlaneY, _hit);
    _ax = _hit[0];
    _az = _hit[2];
    cam.planePoint(b.dx, b.dy, linePlaneY, _hit);
    _bx = _hit[0];
    _bz = _hit[2];
    _targetX = (_ax + _bx) / 2;
    _targetZ = (_az + _bz) / 2;

    final screen = b - a;
    final dx = _bx - _ax, dz = _bz - _az;
    if (screen.distance >= 8 && dx * dx + dz * dz > 1e-6) {
      // Hysteresis so a near-vertical swipe doesn't flip the handle side.
      final sx = screen.dx / screen.distance;
      if (sx < -0.2) _flipped = true;
      if (sx > 0.2) _flipped = false;
      _targetYaw = math.atan2(dz, dx) + (_flipped ? math.pi : 0);
    } else if (snap) {
      _targetYaw = math.atan2(cam.rz, cam.rx);
    }
  }

  KnifeState _copy({
    KnifePhase? phase,
    Offset? guideEnd,
    double? guideOpacity,
    double? x,
    double? z,
    double? yaw,
    double? edgeY,
    double? opacity,
  }) {
    final s = state;
    return KnifeState(
      phase: phase ?? s.phase,
      guideStart: s.guideStart,
      guideEnd: guideEnd ?? s.guideEnd,
      guideOpacity: guideOpacity ?? s.guideOpacity,
      x: x ?? s.x,
      z: z ?? s.z,
      yaw: yaw ?? s.yaw,
      edgeY: edgeY ?? s.edgeY,
      opacity: opacity ?? s.opacity,
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static double _angleDelta(double from, double to) {
    var d = (to - from) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    return d;
  }

  static double _smooth(double e0, double e1, double x) {
    final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}
