// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;
import 'package:orangejelly/features/jelly/physics/jelly_engine.dart'
    as _i960;
import 'package:orangejelly/features/jelly/presentation/cubits/jelly_controls_cubit.dart'
    as _i691;
import 'package:orangejelly/features/jelly/presentation/cubits/jelly_stats_cubit.dart'
    as _i490;
import 'package:orangejelly/features/jelly/presentation/cubits/knife_cubit.dart'
    as _i396;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    gh.lazySingleton<_i960.JellyEngine>(() => _i960.JellyEngine());
    gh.factory<_i691.JellyControlsCubit>(
      () => _i691.JellyControlsCubit(gh<_i960.JellyEngine>()),
    );
    gh.factory<_i490.JellyStatsCubit>(
      () => _i490.JellyStatsCubit(gh<_i960.JellyEngine>()),
    );
    gh.factory<_i396.KnifeCubit>(
      () => _i396.KnifeCubit(gh<_i960.JellyEngine>()),
    );
    return this;
  }
}
