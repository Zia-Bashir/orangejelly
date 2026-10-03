import 'dart:ui';

import 'package:equatable/equatable.dart';

//* --- [ Knife Phase ] ---

enum KnifePhase {
  /// No knife on screen.
  idle,

  /// Finger down: the knife hovers over the drawn line and follows it.
  aiming,

  /// Released: the blade chops down through the jelly (cut fires on impact).
  chopping,

  /// The blade lifts away and fades out.
  lifting,
}

//* --- [ Knife State ] ---

/// Knife tool animation state: the drawn guide line (screen space) and the
/// blade pose (world space: edge midpoint on the ground plane, yaw of the
/// blade axis, height of the cutting edge).
class KnifeState extends Equatable {
  const KnifeState({
    this.phase = KnifePhase.idle,
    this.guideStart,
    this.guideEnd,
    this.guideOpacity = 0,
    this.x = 0,
    this.z = 0,
    this.yaw = 0,
    this.edgeY = 0,
    this.opacity = 0,
  });

  final KnifePhase phase;

  /// Drawn cut line in viewport pixels (null when no line is drawn).
  final Offset? guideStart;
  final Offset? guideEnd;
  final double guideOpacity;

  /// World x / z of the blade centre (over the middle of the cut line).
  final double x;
  final double z;

  /// Blade axis angle in the ground plane (heel → tip).
  final double yaw;

  /// World height of the cutting edge.
  final double edgeY;

  /// 0 = invisible … 1 = fully drawn.
  final double opacity;

  bool get knifeVisible => opacity > 0.001;

  bool get guideVisible =>
      guideStart != null && guideEnd != null && guideOpacity > 0.001;

  @override
  List<Object?> get props => [
    phase,
    guideStart,
    guideEnd,
    guideOpacity,
    x,
    z,
    yaw,
    edgeY,
    opacity,
  ];
}
