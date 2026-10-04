import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'core/di/injection.dart';

//* --- [ Entry Point ] ---

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureDependencies();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
  debugPrint('✅ (APP LOGS) [main] : dependencies configured');
  runApp(const OrangeJellyApp());
}
