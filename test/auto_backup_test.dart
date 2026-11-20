import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_system/auto_backup.dart';
import 'package:task_system/models.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('task_system_backup_test');
    AutoBackup.directory = () async => dir;
  });

  tearDown(() => dir.delete(recursive: true));

  AppData data(String title) => AppData(nextId: 10, quests: [
        Quest(id: 1, title: title, type: QuestType.main, steps: [QuestStep(id: 2, title: 's')]),
      ]);

  test('還沒有備份時，讀出來是 null', () async {
    expect(await AutoBackup.read(), isNull);
  });

  test('一天只備份一次：同一天第二次不會覆蓋', () async {
    final now = DateTime.now();
    expect(await AutoBackup.runDaily(data('早上的'), now), isTrue);
    expect(await AutoBackup.runDaily(data('下午改過的'), now), isFalse);
    expect((await AutoBackup.read())!.data.quests.first.title, '早上的');
  });

  test('隔天會覆蓋成新的一份（只保留一份）', () async {
    await AutoBackup.runDaily(data('昨天的'), DateTime.now());
    // 把檔案時間改成昨天，模擬過了一天
    final file = File('${dir.path}/auto_backup.json');
    await file.setLastModified(DateTime.now().subtract(const Duration(days: 1)));

    expect(await AutoBackup.runDaily(data('今天的'), DateTime.now()), isTrue);
    expect((await AutoBackup.read())!.data.quests.first.title, '今天的');
    expect(dir.listSync().whereType<File>().length, 1); // 只有一份，沒有殘留暫存檔
  });

  test('備份檔壞掉時，讀出來是 null（不會讓 App 出錯）', () async {
    await File('${dir.path}/auto_backup.json').writeAsString('壞掉的內容');
    expect(await AutoBackup.read(), isNull);
  });
}
