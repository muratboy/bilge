import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilge/app_scope.dart';
import 'package:bilge/core/store.dart';
import 'package:bilge/l10n/l10n.dart';
import 'package:bilge/main.dart';
import 'package:bilge/mascot/mascot_art.dart';
import 'package:bilge/screens/profile.dart';
import 'package:bilge/ui/incoming.dart';
import 'package:bilge/ui/theme.dart';

Future<void> _loadFonts() async {
  final nunito = FontLoader('Nunito');
  for (final w in [600, 700, 800, 900]) {
    final f = File('assets/fonts/Nunito-$w.ttf');
    if (f.existsSync()) {
      nunito.addFont(f.readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
  }
  await nunito.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFonts();
  });

  testWidgets('hatırlatıcı açılırken platform başarısız dönerse ayar kapanır ve uyarı görünür', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 892)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const reminderChannel = MethodChannel('bilge/reminder');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(reminderChannel, (call) async {
      if (call.method == 'schedule') {
        final enabled = call.arguments['enabled'] as bool? ?? false;
        if (enabled) return false;
      }
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(reminderChannel, null));

    final storage = MemoryStorage();
    final app = AppState(storage);
    await app.load();
    app.companion = MascotId.puhu;
    app.settings.reminder = false;

    await tester.pumpWidget(
      AppScope(
        state: app,
        child: MaterialApp(
          theme: buildTheme(Palette.light),
          home: const Scaffold(body: ProfileScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Ayarlara kaydır ve hatırlatıcı anahtarını açmayı dene
    final toggleFinder = find.byKey(const ValueKey('set-reminder-toggle'));
    await tester.scrollUntilVisible(toggleFinder, 250, scrollable: find.byType(Scrollable).first);
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(toggleFinder);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(app.settings.reminder, isFalse);
    expect(find.text(t('reminder.permissionDenied')), findsOneWidget);
  });

  testWidgets('gelen içerik okunamadı bildirimi gelince uyarı görünür', (tester) async {
    const incomingChannel = MethodChannel('bilge/incoming');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, (call) async {
      if (call.method == 'take') return null;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, null));

    final storage = MemoryStorage();
    final app = AppState(storage);
    await app.load();
    app.companion = MascotId.puhu;

    await tester.pumpWidget(BilgeApp(state: app));
    await tester.pump(const Duration(milliseconds: 300));

    // Uygulama açıkken okunamayan içerik bildirimi gelir
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'bilge/incoming',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('incoming', Incoming.readFailed)),
      (_) {},
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(t('import.fileFailed')), findsOneWidget);
  });

  testWidgets('içerik taşımayan açılışta uyarı görünmez', (tester) async {
    const incomingChannel = MethodChannel('bilge/incoming');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, (call) async {
      if (call.method == 'take') return null;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, null));

    final storage = MemoryStorage();
    final app = AppState(storage);
    await app.load();
    app.companion = MascotId.puhu;

    await tester.pumpWidget(BilgeApp(state: app));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(t('import.fileFailed')), findsNothing);
    expect(find.text(t('incoming.failed')), findsNothing);
  });

  testWidgets('açılışta okunamayan dosya geldiğinde uyarı görünür', (tester) async {
    const incomingChannel = MethodChannel('bilge/incoming');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, (call) async {
      if (call.method == 'take') return Incoming.readFailed;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, null));

    final storage = MemoryStorage();
    final app = AppState(storage);
    await app.load();
    app.companion = MascotId.puhu;

    await tester.pumpWidget(BilgeApp(state: app));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(t('import.fileFailed')), findsOneWidget);
  });
}
