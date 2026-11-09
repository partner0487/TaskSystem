import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'notifications.dart';
import 'store.dart';
import 'theme.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = QuestStore();
  await Notifier.init(onDataChanged: store.reload);

  runApp(QuestApp(store: store));

  // 畫面出來後再要通知權限，然後讀資料並同步通知欄
  await Notifier.requestPermission();
  await store.reload();
}

/// 手機開機後，Android 原生的 BootReceiver 會啟動一個沒有畫面的 Flutter 引擎執行這裡，
/// 把未完成任務的通知補回通知欄（重開機會清空所有通知）。
@pragma('vm:entry-point')
Future<void> bootSync() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await Notifier.refreshFromStorage();
}

class QuestApp extends StatelessWidget {
  const QuestApp({super.key, required this.store});

  final QuestStore store;

  static const _zhTW = Locale.fromSubtags(
      languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '任務系統',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // 讓日期 / 時間選擇器顯示中文
      locale: _zhTW,
      supportedLocales: const [_zhTW],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: HomePage(store: store),
    );
  }
}
