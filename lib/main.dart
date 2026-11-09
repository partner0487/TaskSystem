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

class QuestApp extends StatelessWidget {
  const QuestApp({super.key, required this.store});

  final QuestStore store;

  static const _zhTW = Locale.fromSubtags(
      languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '任務',
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
