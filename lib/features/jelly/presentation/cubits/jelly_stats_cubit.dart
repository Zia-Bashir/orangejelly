import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../physics/jelly_engine.dart';

//* --- [ Jelly Stats Cubit ] ---

/// Live specimen readouts. [refresh] is polled at ~10 Hz by the viewport;
/// values are rounded to display precision so unchanged readouts don't
/// trigger rebuilds.
@injectable
class JellyStatsCubit extends Cubit<JellyStats> {
  JellyStatsCubit(this._engine) : super(_rounded(_engine.computeStats()));

  final JellyEngine _engine;

  void refresh() {
    final next = _rounded(_engine.computeStats());
    if (next != state) emit(next);
  }

  static JellyStats _rounded(JellyStats s) => JellyStats(
    massGrams: s.massGrams.roundToDouble(),
    volumePercent: (s.volumePercent * 10).roundToDouble() / 10,
    kineticMicroJoules: (s.kineticMicroJoules * 100).roundToDouble() / 100,
    pieces: s.pieces,
    particles: s.particles,
    tetrahedra: s.tetrahedra,
  );
}
