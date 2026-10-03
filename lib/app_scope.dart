import 'package:flutter/widgets.dart';

import 'core/store.dart';

/// [AppState]'i ağacın her yerinden erişilebilir kılar; durum değişince bağımlı ekranlar yenilenir.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  /// Ekran durumu izler: değişiklikte yeniden çizilir.
  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Yalnızca okur (initState ve olay işleyicileri için).
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
