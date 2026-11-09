# 任務系統

參考原神任務介面的 Android 待辦清單 App，用 Flutter 開發。
未完成的任務會常駐在**通知欄**，完成後勾選，通知就會自動消失。

## 功能

- **四種分類**：主線任務、支線任務、每週任務、每日委託
- **大事件 → 細項**：每個大事件（例如「期末考」）底下可以有多個細項（例如「讀第三章」）
- **期限可有可無**：細項可以設定截止時間，也可以不設，當成記事本使用
- **通知欄常駐**：每個未完成的細項都是一則常駐通知，不會響鈴打擾；滑掉會自動彈回
- **在通知欄直接完成**：通知上有「✓ 完成」按鈕，App 沒開也能勾選
- **每日自動重置**：每日委託在每天凌晨 4:00 重置（跟原神一樣），App 沒開也會重新出現
- **每週任務**：可勾選星期幾（例如「每週一、三、五運動」），只在那幾天出現、當天 24:00 截止；
  沒勾就是整週都在、週日 24:00 截止。時間到就自動消失，不會顯示「已逾期」
- **主線／支線的期限**：可自己設定；逾期滿 7 天自動移出通知欄（App 裡仍保留，由你決定完成或刪除）
- **到期前震動提醒**（主線／支線）：可選 10 分鐘／1 小時／1 天前，只震動不響鈴（預設 1 小時前）
- **倒數顯示**：剩 X 天 Y 小時 → 剩 X 小時 Y 分 → 剩 X 分 Y 秒；24 小時內通知上也會顯示倒數計時
- **開機自動補回**：重開機後通知會自動回到通知欄

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

## 備份與換手機

右上角 ⋮ → **匯出備份**，存成一個 `.json` 檔（可以存到下載資料夾、Google 雲端硬碟…）。
換手機或重裝時，⋮ → **匯入備份** 選那個檔案即可。匯入會取代目前所有任務，按錯可以馬上「復原」。

## 發佈新版本（GitHub Releases + gh）

### 一次性設定

1. 安裝 GitHub CLI：`winget install GitHub.cli`
2. 登入：`gh auth login`，依序選 **GitHub.com → HTTPS → Login with a web browser**，
   把畫面上的 8 碼代碼貼到瀏覽器開啟的頁面
3. 確認：`gh auth status`

### 簽章金鑰（非常重要）

正式版用 `android/key.properties` 指定的金鑰簽章，**這個檔案和金鑰 `.jks` 都不在 git 裡**。

- 每次更新都必須用**同一把金鑰**，否則使用者無法直接升級，只能刪掉重裝（資料會消失）
- 請把 `.jks` 和 `key.properties` 備份到安全的地方（密碼管理器、加密的雲端硬碟）
- 沒有 `key.properties` 時，release 會改用 debug 金鑰（只適合自己測試，不要拿去發佈）

### 每次發佈的步驟

```bash
# 1. 改版本號：pubspec.yaml 的 version，+ 後面的數字每次都要變大
#    例如 1.0.0+1 → 1.0.1+2

# 2. 確認測試都通過
flutter test

# 3. 編譯（依手機 CPU 分開打包；一般手機用 arm64-v8a）
flutter build apk --release --split-per-abi

# 4. 改成好認的檔名
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk TaskSystem-v1.0.1.apk

# 5. 先建立「草稿」，到網頁上確認內容（只有自己看得到）
gh release create v1.0.1 TaskSystem-v1.0.1.apk --title "v1.0.1" --notes-file release-notes.md --draft
gh release view v1.0.1 --web

# 6. 確認沒問題後正式公開
gh release edit v1.0.1 --draft=false
```

### 其他常用指令

| 指令 | 用途 |
|---|---|
| `gh release list` | 列出所有版本 |
| `gh release view v1.0.1` | 查看某個版本的內容 |
| `gh release upload v1.0.1 檔案.apk --clobber` | 補傳或替換某個版本的檔案 |
| `gh release edit v1.0.1 --notes-file notes.md` | 修改版本說明 |
| `gh release delete v1.0.1 --cleanup-tag` | 刪除版本（連同 git tag） |

### 給下載者的安裝說明（可以貼在版本說明裡）

1. 下載 `TaskSystem-vX.Y.Z.apk`，點開安裝
2. 如果跳出「不允許安裝不明應用程式」，依畫面指示允許這次安裝
3. 如果 Play Protect 警告「未知的開發人員」，點「更多詳細資料 → 仍要安裝」
4. 第一次打開時**允許通知**，任務才會出現在通知欄
5. Samsung 手機建議：設定 → 電池 → 背景使用限制，把「任務系統」設為**不受限制**

## 已知限制

- 每日／每週的重新出現用省電的不精確鬧鐘，可能比 04:00 晚一點（最多約 1 小時）
- 震動提醒的強度、要不要響鈴，可以到 Android 設定 → 通知 → 任務系統 → **到期提醒** 自行調整
- Samsung 的省電機制可能影響背景功能：若「在通知欄按完成」或「滑掉彈回」沒有作用，請到 設定 → 電池 → 背景使用限制，把「任務系統」設為**不受限制**

## 使用的套件

- [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications)：通知欄
- [shared_preferences](https://pub.dev/packages/shared_preferences)：資料儲存
- flutter_localizations：日期／時間選擇器中文化
