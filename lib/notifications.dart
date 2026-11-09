import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';
import 'storage.dart';

const _channelId = 'quests';
const _channelName = '待辦任務';
const _actionComplete = 'complete';
const _uiPortName = 'quest_ui_port';

/// 每日委託「凌晨 4 點重新出現」的預約通知，id 用 細項 id + 這個偏移量，
/// 才不會跟正在顯示的通知（id = 細項 id）互相取消。
const _resetIdOffset = 1000000;

/// 到期前的震動提醒，id = 細項 id + 這個偏移量。
const _reminderIdOffset = 2000000;
const _reminderChannelId = 'reminders';

/// 通知欄的事件（按「完成」、把通知滑掉）由 Android 另外開一個背景 isolate 執行，
/// 就算 App 完全沒開也一樣。@pragma 讓編譯器不會把它當成沒用到的程式碼刪掉。
@pragma('vm:entry-point')
Future<void> onBackgroundNotificationResponse(NotificationResponse r) async {
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

  /// [onDataChanged]：背景改了資料（在通知欄按了完成等）時，叫畫面重新讀取。
  static Future<void> init({required Future<void> Function() onDataChanged}) async {
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_quest'),
      ),
      onDidReceiveNotificationResponse: handleResponse,
      onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationResponse,
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

  /// 通知欄的事件：
  /// - 按「✓ 完成」→ 把那個細項標成完成
  /// - 把通知滑掉 → 什麼都不改，重新同步時就會把它補回來（滑不掉的效果）
  /// - 點通知本身 → 只是打開 App，不用處理
  static Future<void> handleResponse(NotificationResponse r) async {
    final type = r.notificationResponseType;
    final complete = type == NotificationResponseType.selectedNotificationAction &&
        r.actionId == _actionComplete;
    final dismissed = type == NotificationResponseType.notificationDismissed;
    if (!complete && !dismissed) return;

    // payload 一定是細項 id（預約重置的通知 id 有加偏移量，不能直接用）
    final stepId = int.tryParse(r.payload ?? '') ?? r.id;
    await refreshFromStorage(completeStepId: complete ? stepId : null);
  }

  /// 讀存檔 → 套用每日重置 →（可選）完成某個細項 → 存檔 → 同步通知欄。
  /// 通知欄事件和開機補發都走這條路。
  static Future<void> refreshFromStorage({int? completeStepId}) async {
    final data = await Storage.read();
    data.applyResets(DateTime.now());
    if (completeStepId != null) {
      for (final s in data.quests.expand((q) => q.steps)) {
        if (s.id == completeStepId) s.done = true;
      }
    }
    await Storage.write(data);
    await sync(data);

    // 如果 App 正開著，通知畫面更新
    IsolateNameServer.lookupPortByName(_uiPortName)?.send('changed');
  }

  /// 讓通知欄跟資料一致：
  /// 1. 未完成的細項顯示 / 更新；有設提醒的，預約到期前的震動提醒
  /// 2. 其它通知、預約全部移除
  /// 3. 已完成的每日 / 每週任務，預約在下次重置時重新出現（App 沒開也會出現）
  static Future<void> sync(AppData data) async {
    final now = DateTime.now();
    final keepActive = <int>{};
    final keepPending = <int>{};
    final resets = <(Quest, QuestStep, DateTime)>[];
    final reminders = <(Quest, QuestStep, DateTime)>[];

    for (final q in data.quests) {
      for (final s in q.steps) {
        // 到期提醒（只有主線 / 支線有手動期限）：只要還沒完成就照常提醒
        if (!s.done && !q.type.recurring) {
          keepActive.add(_reminderIdOffset + s.id); // 已經跳出的提醒留著，等使用者自己處理
          final at = s.remindAt;
          if (at != null && at.isAfter(now)) {
            keepPending.add(_reminderIdOffset + s.id);
            reminders.add((q, s, at));
          }
        }

        // 逾期超過 7 天的主線 / 支線不再放通知欄（App 裡還看得到）
        if (isStale(q.type, s, now)) continue;

        if (!s.done && isActiveOn(q.type, s, now)) {
          keepActive.add(s.id);
          await plugin.show(
            id: s.id, // 用細項 id 當通知 id，才能精準取消
            title: s.title,
            body: _body(q, s, now),
            payload: '${s.id}',
            notificationDetails: _details(q, s, now),
          );
        } else {
          // 已完成的每日 / 每週，或今天不是它的日子（例如週一的「週六日籃球」）：
          // 預約在下一個該出現的日子凌晨 4 點出現
          final at = nextResetFor(q.type, s, now);
          if (at != null) {
            keepPending.add(_resetIdOffset + s.id);
            resets.add((q, s, at));
          }
        }
      }
    }

    // 先清掉不該存在的通知與預約（cancel 會同時取消同 id 的預約，所以要在重新預約之前做）
    for (final n in await plugin.getActiveNotifications()) {
      if (n.id != null && !keepActive.contains(n.id)) await plugin.cancel(id: n.id!);
    }
    for (final p in await plugin.pendingNotificationRequests()) {
      if (!keepPending.contains(p.id)) await plugin.cancel(id: p.id);
    }

    // 預約下次重置時重新出現。用不精確的鬧鐘（可能晚一點），不需要額外權限也比較省電。
    for (final (q, s, at) in resets) {
      await plugin.zonedSchedule(
        id: _resetIdOffset + s.id,
        scheduledDate: tz.TZDateTime.from(at, tz.UTC),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: s.title,
        body: _body(q, s, at),
        payload: '${s.id}',
        notificationDetails: _details(q, s, at),
      );
    }

    // 到期前的震動提醒要準時，用精確鬧鐘；萬一系統不允許就退回不精確的。
    for (final (q, s, at) in reminders) {
      Future<void> schedule(AndroidScheduleMode mode) => plugin.zonedSchedule(
            id: _reminderIdOffset + s.id,
            scheduledDate: tz.TZDateTime.from(at, tz.UTC),
            androidScheduleMode: mode,
            title: '${durationText(s.remindBefore!)}後到期：${s.title}',
            body: notificationDeadlineText(s, q.type, at),
            payload: '${s.id}',
            notificationDetails: _reminderDetails(q),
          );
      try {
        await schedule(AndroidScheduleMode.exactAllowWhileIdle);
      } catch (_) {
        await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
      }
    }
  }

  /// 震動提醒：獨立的通知類別，會從畫面上方滑出、震動，但不響鈴。
  /// 使用者可以在 Android 設定 → 通知 → 任務系統 → 到期提醒 自己調整。
  static NotificationDetails _reminderDetails(Quest q) => NotificationDetails(
        android: AndroidNotificationDetails(
          _reminderChannelId,
          '到期提醒',
          channelDescription: '截止前震動提醒（不響鈴）',
          icon: 'ic_stat_quest',
          importance: Importance.high, // 從畫面上方滑出
          priority: Priority.high,
          playSound: false,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 250, 150, 250]), // 震兩下
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
      );

  static String _body(Quest q, QuestStep s, DateTime now) => [
        notificationDeadlineText(s, q.type, now),
        if (s.note.isNotEmpty) s.note,
      ].join('・');

  static NotificationDetails _details(Quest q, QuestStep s, DateTime now) {
    // 24 小時內到期：通知右上角顯示會自己倒數的計時器
    final d = effectiveDeadline(q.type, s, now); // 每週任務會自動有期限
    final countdown = d != null && d.isAfter(now) && d.difference(now) <= const Duration(hours: 24);

    // 到時間由系統自動移除通知（App 沒開也會準時消失）：
    // 每週任務 → 晚上 12 點；主線 / 支線 → 逾期滿 7 天
    final removeAt = q.type == QuestType.weekly ? d : notificationHideAt(q.type, s);
    final timeout = removeAt != null && removeAt.isAfter(now) ? removeAt.difference(now) : null;

    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: '尚未完成的任務會常駐在通知欄',
        icon: 'ic_stat_quest', // 背景 isolate 也能正確顯示圖示
        importance: Importance.low, // 不響鈴、不跳出，安靜地待在通知欄
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        // 被滑掉時通知背景 isolate，重新補上（App 沒開也會觸發）
        dismissIsolate: NotificationDismissedIsolate.background,
        // 只有倒數時才指定 when（截止時間在未來）。
        // 不要指定過去的時間：Android 會直接丟掉時間戳太舊的通知。
        showWhen: countdown,
        when: countdown ? d.millisecondsSinceEpoch : null,
        usesChronometer: countdown,
        chronometerCountDown: countdown,
        timeoutAfter: timeout?.inMilliseconds,
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
    );
  }
}
