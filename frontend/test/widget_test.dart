import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:LenDen/utils/theme_provider.dart';
import 'package:LenDen/utils/locale_provider.dart';
import 'package:LenDen/session.dart';
import 'package:LenDen/splash_screen.dart';

Widget _appProviders({required Widget child}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => SessionProvider()),
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('SplashScreen renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      _appProviders(child: const SplashScreen(autoNavigate: false)),
    );
    await tester.pump(Duration.zero);
    // The splash screen should be present in the widget tree
    expect(find.byType(SplashScreen), findsOneWidget);
  });
}
