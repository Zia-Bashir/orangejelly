import 'package:equatable/equatable.dart';

import '../../render/jelly_palette.dart';

//* --- [ Jelly Tool ] ---

enum JellyTool {
  hand('Hand'),
  knife('Knife');

  const JellyTool(this.label);

  final String label;
}

//* --- [ Jelly Controls State ] ---

class JellyControlsState extends Equatable {
  const JellyControlsState({
    this.tool = JellyTool.hand,
    this.variety = JellyVariety.crimson,
    this.firmness = 0.40,
    this.damping = 0.45,
    this.quarterSpeed = false,
    this.showMesh = false,
    this.paused = false,
    this.panelExpanded = false,
    this.insideExpanded = false,
  });

  final JellyTool tool;
  final JellyVariety variety;
  final double firmness;
  final double damping;
  final bool quarterSpeed;
  final bool showMesh;
  final bool paused;

  /// Portrait layouts: whether the bottom controls sheet is expanded.
  final bool panelExpanded;

  /// Whether the "Inside the experiment" note is open.
  final bool insideExpanded;

  double get timeScale => quarterSpeed ? 0.25 : 1.0;

  JellyControlsState copyWith({
    JellyTool? tool,
    JellyVariety? variety,
    double? firmness,
    double? damping,
    bool? quarterSpeed,
    bool? showMesh,
    bool? paused,
    bool? panelExpanded,
    bool? insideExpanded,
  }) {
    return JellyControlsState(
      tool: tool ?? this.tool,
      variety: variety ?? this.variety,
      firmness: firmness ?? this.firmness,
      damping: damping ?? this.damping,
      quarterSpeed: quarterSpeed ?? this.quarterSpeed,
      showMesh: showMesh ?? this.showMesh,
      paused: paused ?? this.paused,
      panelExpanded: panelExpanded ?? this.panelExpanded,
      insideExpanded: insideExpanded ?? this.insideExpanded,
    );
  }

  @override
  List<Object?> get props => [
    tool,
    variety,
    firmness,
    damping,
    quarterSpeed,
    showMesh,
    paused,
    panelExpanded,
    insideExpanded,
  ];
}
