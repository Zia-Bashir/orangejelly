import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../physics/jelly_engine.dart';
import '../../render/jelly_palette.dart';
import 'jelly_controls_state.dart';

//* --- [ Jelly Controls Cubit ] ---

/// UI state of the specimen panel. Physical settings are forwarded to the
/// [JellyEngine] so the simulation always mirrors what the panel shows.
@injectable
class JellyControlsCubit extends Cubit<JellyControlsState> {
  JellyControlsCubit(this._engine) : super(const JellyControlsState()) {
    _engine
      ..firmness = state.firmness
      ..damping = state.damping;
  }

  final JellyEngine _engine;

  //* ---[ Tool + variety ]---

  void selectTool(JellyTool tool) {
    if (tool == state.tool) return;
    _engine.endGrab();
    debugPrint('✅ (APP LOGS) [controls] : tool -> ${tool.name}');
    emit(state.copyWith(tool: tool));
  }

  void selectVariety(JellyVariety variety) {
    if (variety == state.variety) return;
    debugPrint('✅ (APP LOGS) [controls] : variety -> ${variety.name}');
    emit(state.copyWith(variety: variety));
  }

  //* ---[ Sliders ]---

  void setFirmness(double value) {
    final v = value.clamp(0.0, 1.0);
    _engine.firmness = v;
    emit(state.copyWith(firmness: v));
  }

  void setDamping(double value) {
    final v = value.clamp(0.0, 1.0);
    _engine.damping = v;
    emit(state.copyWith(damping: v));
  }

  //* ---[ Toggles ]---

  void toggleQuarterSpeed() =>
      emit(state.copyWith(quarterSpeed: !state.quarterSpeed));

  void toggleShowMesh() => emit(state.copyWith(showMesh: !state.showMesh));

  void togglePaused() {
    debugPrint('✅ (APP LOGS) [controls] : paused -> ${!state.paused}');
    emit(state.copyWith(paused: !state.paused));
  }

  void togglePanel() =>
      emit(state.copyWith(panelExpanded: !state.panelExpanded));

  void toggleInside() =>
      emit(state.copyWith(insideExpanded: !state.insideExpanded));

  //* ---[ Actions ]---

  void nudge() => _engine.nudge();

  void reset() => _engine.reset();
}
