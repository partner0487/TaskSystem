# 任務系統

參考原神任務介面的 Android 待辦清單 App，用 Flutter 開發。
未完成的任務會常駐在**通知欄**，完成後勾選，通知就會自動消失。

## 功能

- **三種分類**：主線任務、支線任務、每日委託
- **大事件 → 細項**：每個大事件（例如「期末考」）底下可以有多個細項（例如「讀第三章」）
- **期限可有可無**：細項可以設定截止時間，也可以不設，當成記事本使用
- **通知欄常駐**：每個未完成的細項都是一則常駐通知，不會響鈴打擾
- **在通知欄直接完成**：通知上有「✓ 完成」按鈕，App 沒開也能勾選
- **每日自動重置**：每日委託在每天凌晨 4:00 重置（跟原神一樣）
- **快到期提示**：24 小時內到期的細項，卡片左側會出現藍色條

## 操作方式

| 想做的事 | 操作 |
|---|---|
| 新增大事件 | 點右下角的 ＋ |
| 新增細項 | 點大事件底下的「新增細項」，或標題右邊的 ⋮ → 新增細項 |
| 完成細項 | 點卡片右側的 ✓，或在通知欄按「✓ 完成」 |
| 查看備註 | 點一下細項卡片（會變成米白色並展開備註） |
| 編輯細項 | 長按細項卡片 |
| 刪除細項 | 細項卡片往左滑 |
| 編輯／刪除大事件 | 大事件標題右邊的 ⋮ |
| 展開／收合大事件 | 點大事件標題 |

## 專案結構

```
lib/
├── main.dart            App 進入點：初始化通知、要求權限、讀取資料
├── models.dart          資料結構（分類、大事件、細項）與期限文字
├── storage.dart         存檔讀寫（shared_preferences，存成 JSON）
├── store.dart           狀態管理：新增／修改／刪除都經過這裡，並同步通知欄
├── notifications.dart   通知欄：顯示、移除通知，處理「✓ 完成」按鈕
├── theme.dart           原神風格配色
└── ui/
    ├── home_page.dart   主畫面（分類分頁 + 任務列表）
    ├── widgets.dart     菱形圖示、大事件標題、細項卡片等元件
    └── edit_sheets.dart 新增／編輯用的底部表單
```

## 開發環境

- Flutter 3.47 以上（Dart 3.13）
- JDK 17
- Android SDK（API 37 編譯，最低支援 Android 7.0 / API 24）
- 編輯器：VS Code + Flutter 擴充套件（不需要 Android Studio）

## 在手機上執行

1. 手機開啟**開發人員選項**：設定 → 關於手機 → 軟體資訊 → 連點「版本號碼」7 次
2. 開發人員選項 → 打開 **USB 偵錯**
3. Samsung 手機要另外關閉：設定 → 安全性與隱私 → **自動封鎖程式**
4. 用 USB 線接上電腦，手機上按「允許 USB 偵錯」
5. 在 VS Code 開啟本專案，確認右下角選到你的手機，按 **F5**

修改 Dart 程式碼後存檔即可**熱重載**；修改通知相關的程式碼請按 **Ctrl + Shift + F5** 熱重啟；
修改 `android/` 底下的檔案（圖示、App 名稱、權限）則需要停止後重新按 F5。

## 常用指令

```bash
flutter pub get          # 安裝套件
flutter run              # 在已連接的手機上執行
flutter test             # 執行測試
flutter analyze          # 靜態檢查
flutter build apk        # 打包 APK（輸出在 build/app/outputs/flutter-apk/）
```

## 已知限制

- **手機重開機後通知會消失**，需要打開 App 一次才會補回來
- **Android 14 以上**，常駐通知仍可被使用者手動滑掉；回到 App 時會自動補回
- Samsung 的省電機制可能影響「在通知欄按完成」：若沒有作用，請到 設定 → 電池 → 背景使用限制，把「任務系統」設為**不受限制**

## 使用的套件

- [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications)：通知欄
- [shared_preferences](https://pub.dev/packages/shared_preferences)：資料儲存
- flutter_localizations：日期／時間選擇器中文化
