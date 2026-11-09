import 'package:flutter/material.dart';

/// 參考原神任務介面的配色。
class GColors {
  static const bgTop = Color(0xFF1B2130);
  static const bgBottom = Color(0xFF2A3245);
  static const header = Color(0xFF2B3244); // 大事件標題底色
  static const card = Color(0xFF3B4357); // 細項卡片底色
  static const cardSelected = Color(0xFFECE5D8); // 選中時的米白色
  static const gold = Color(0xFFD3BC8E);
  static const goldBright = Color(0xFFF1D9A6);
  static const text = Color(0xFFECE5D8);
  static const textDark = Color(0xFF495366);
  static const sub = Color(0xFFA9A79F);
  static const overdue = Color(0xFFE07A6B);
  static const accent = Color(0xFF4FB3E8); // 左側藍色條
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: GColors.gold,
      brightness: Brightness.dark,
      primary: GColors.gold,
      surface: GColors.header,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: GColors.bgTop,
    textTheme: base.textTheme.apply(
      bodyColor: GColors.text,
      displayColor: GColors.text,
    ),
    // 下方「已刪除・復原」提示：米白底、深色字、金色按鈕
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: GColors.cardSelected,
      contentTextStyle: TextStyle(color: GColors.textDark, fontSize: 15),
      actionTextColor: Color(0xFF9A7B3F),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: GColors.gold, width: 1.5),
      ),
    ),
  );
}
