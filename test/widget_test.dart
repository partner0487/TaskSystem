import 'package:flutter_test/flutter_test.dart';
import 'package:task_system/models.dart';

void main() {
  test('存檔轉成 JSON 再讀回來，內容不變', () {
    final data = AppData.sample();
    final back = AppData.fromJson(data.toJson());
    expect(back.toJson(), data.toJson());
  });

  test('每日重置以凌晨 4 點為分界', () {
    expect(resetDayKey(DateTime(2026, 11, 9, 3, 59)), '2026-11-8');
    expect(resetDayKey(DateTime(2026, 11, 9, 4, 0)), '2026-11-9');
  });

  test('沒有期限的任務顯示「無期限」', () {
    final s = QuestStep(id: 1, title: '牛奶');
    expect(deadlineText(s, QuestType.memo, DateTime.now()), '無期限');
    expect(deadlineText(s, QuestType.daily, DateTime.now()), '每日 04:00 重置');
  });
}
