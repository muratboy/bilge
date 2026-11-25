import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_scope.dart';
import 'core/store.dart';
import 'l10n/l10n.dart';
import 'screens/home.dart';
import 'screens/manage.dart';
import 'screens/welcome.dart';
import 'ui/incoming.dart';
import 'ui/io.dart';
import 'ui/piper_downloader.dart';
import 'ui/sfx.dart';
import 'ui/speech.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
    unawaited(PiperVoiceDownloader.cleanPartFiles());
  }
  final state = AppState(FileStorage());
  Speech.selectedVoiceResolver = (lang) {
    final norm = lang.replaceAll('-', '_').toLowerCase().trim();
    final primary = norm.split('_').first;
    return state.settings.selectedVoices[norm] ??
        state.settings.selectedVoices[primary] ??
        state.settings.selectedVoices[lang];
  };
  await state.load();
  if (state.settings.reminder) {
    final device = PlatformDispatcher.instance.locale.languageCode;
    L.code = state.settings.lang == 'auto' ? (device == 'tr' ? 'tr' : 'en') : state.settings.lang;
    scheduleReminder(
      enabled: true,
      hour: state.settings.reminderHour,
      title: t('reminder.notifTitle'),
      body: t('reminder.notifBody'),
      lastActive: state.profile.lastActive,
    );
  }
  final initialIncoming = await Incoming.readArgs(args);
  runApp(BilgeApp(state: state, initialIncoming: initialIncoming));
}

class BilgeApp extends StatelessWidget {
  const BilgeApp({super.key, required this.state, this.initialIncoming});
  final AppState state;
  final String? initialIncoming;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          // Dil ve ses, ayarlardan her değişiklikte yeniden okunur
          final device = PlatformDispatcher.instance.locale.languageCode;
          L.code = state.settings.lang == 'auto' ? (device == 'tr' ? 'tr' : 'en') : state.settings.lang;
          Sfx.enabled = state.settings.sound;
          return AppScope(
            state: state,
            child: MaterialApp(
              title: 'Bilge',
              debugShowCheckedModeBanner: false,
              theme: buildTheme(Palette.light),
              darkTheme: buildTheme(Palette.night),
              themeMode: switch (state.settings.theme) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system },
              locale: Locale(L.code),
              supportedLocales: const [Locale('tr'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: _Root(initialIncoming: initialIncoming),
            ),
          );
        },
      );
}

/// Yol arkadaşı seçilene kadar karşılama, sonra ana ekran.
/// Başka uygulamadan gelen kurs dosyası varsa, ana ekrana geçilince kullanıcıya sorulur.
class _Root extends StatefulWidget {
  const _Root({this.initialIncoming});
  final String? initialIncoming;
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  String? _incoming;

  @override
  void initState() {
    super.initState();
    _incoming = widget.initialIncoming;
    Incoming.listen((text) {
      if (mounted) setState(() => _incoming = text);
    });
    refreshSampleCourses(AppScope.read(context));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ready = app.companion != null;
    final notice = app.consumeRecoveryNotice();
    if (notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        toast(context, t(notice));
      });
    }
    final text = _incoming;
    if (text == Incoming.readFailed && !ready) {
      _incoming = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        toast(context, t('import.fileFailed'));
      });
    } else if (ready && text != null) {
      _incoming = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).popUntil((r) => r.isFirst);
        offerIncomingCourse(context, text);
      });
    }
    return ready ? const HomeShell() : const WelcomeScreen();
  }
}
