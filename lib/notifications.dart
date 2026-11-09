import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'models.dart';
import 'storage.dart';

const _channelId = 'quests';
const _channelName = '待辦任務';
const _actionComplete = 'complete';
const _uiPortName = 'quest_ui_port';

/// 使用者在通知欄按「完成」時，Android 會另外開一個背景 isolate 執行這個函式，
/// 就算 App 完全沒開也一樣。@pragma 讓編譯器不會把它當成沒用到的程式碼刪掉。
@pragma('vm:entry-point')
Future<void> onBackgroundNotificationAction(NotificationResponse r) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await Notifier.handleResponse(r);
}

/// 通知欄相關的一切：每個未完成的細項 = 一則常駐通知。
class Notifier {
  static final plugin = FlutterLocalNotificationsPlugin();
  static final _uiPort = ReceivePort();

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// [onDataChanged]：背景改了資料（在通知欄按了完成）時，叫畫面重新讀取。
  static Future<void> init({required Future<void> Function() onDataChanged}) async {
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_quest'),
      ),
      onDidReceiveNotificationResponse: handleResponse,
      onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationAction,
    );

    // 背景 isolate 改完資料後會傳訊息過來，這邊收到就重新讀取
    IsolateNameServer.removePortNameMapping(_uiPortName);
    IsolateNameServer.registerPortWithName(_uiPort.sendPort, _uiPortName);
    _uiPort.listen((_) => onDataChanged());
  }

  /// Android 13 以上要跳出視窗詢問使用者是否允許通知。
  static Future<void> requestPermission() async {
    await _android?.requestNotificationsPermission();
  }

  /// 處理通知的點擊。只處理「完成」按鈕，點通知本身只會打開 App。
  static Future<void> handleResponse(NotificationResponse r) async {
    if (r.actionId != _actionComplete) return;
    final stepId = r.id ?? int.tryParse(r.payload ?? '');
    if (stepId == null) return;

    final data = await Storage.read();
    for (final s in data.quests.expand((q) => q.steps)) {
      if (s.id == stepId) s.done = true;
    }
    await Storage.write(data);
    // 通知本身會因為 cancelNotification: true 自動消失

    // 如果 App 正開著，通知畫面更新
    IsolateNameServer.lookupPortByName(_uiPortName)?.send('changed');
  }

  /// 讓通知欄跟資料一致：未完成的細項顯示 / 更新，其它的全部移除。
  static Future<void> sync(AppData data) async {
    final now = DateTime.now();
    final openIds = <int>{};

    for (final q in data.quests) {
      for (final s in q.steps.where((s) => !s.done)) {
        openIds.add(s.id);
        await _show(q, s, now);
      }
    }

    final active = await plugin.getActiveNotifications();
    for (final n in active) {
      if (n.id != null && !openIds.contains(n.id)) {
        await plugin.cancel(id: n.id!);
      }
    }
  }

  static Future<void> _show(Quest q, QuestStep s, DateTime now) {
    final body = [
      deadlineText(s, q.type, now),
      if (s.note.isNotEmpty) s.note,
    ].join('・');

    return plugin.show(
      id: s.id, // 用細項 id 當通知 id，才能精準取消
      title: s.title,
      body: body,
      payload: '${s.id}',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: '尚未完成的任務會常駐在通知欄',
          importance: Importance.low, // 不響鈴、不跳出，安靜地待在通知欄
          priority: Priority.low,
          ongoing: true, // 常駐（Android 14+ 仍可被滑掉，回到 App 時會補回來）
          autoCancel: false,
          onlyAlertOnce: true,
          // 不要自己指定 when：Android 會直接丟掉時間戳太舊（例如 1970 年）的通知
          showWhen: false,
          subText: '${q.type.label}・${q.title}',
          color: const Color(0xFFD3BC8E),
          category: AndroidNotificationCategory.reminder,
          actions: const [
            AndroidNotificationAction(
              _actionComplete,
              '✓ 完成',
              cancelNotification: true,
              showsUserInterface: false,
            ),
          ],
        ),
      ),
    );
  }
}
