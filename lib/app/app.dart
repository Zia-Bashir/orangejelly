import 'package:flutter/material.dart';

import '../features/jelly/presentation/pages/jelly_page.dart';
import 'theme.dart';

//* --- [ Orange Jelly App ] ---

class OrangeJellyApp extends StatelessWidget {
  const OrangeJellyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orange Jelly',
      debugShowCheckedModeBanner: false,
      theme: buildJellyTheme(),
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.2,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const JellyPage(),
    );
  }
}
