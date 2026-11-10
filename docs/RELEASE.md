# 發佈新版本（GitHub Releases + gh）

給維護者看的發佈流程。

## 一次性設定

1. 安裝 GitHub CLI：`winget install GitHub.cli`
2. 登入：`gh auth login`，依序選 **GitHub.com → HTTPS → Login with a web browser**，
   把畫面上的 8 碼代碼貼到瀏覽器開啟的頁面
3. 確認：`gh auth status`

## 簽章金鑰（非常重要）

正式版用 `android/key.properties` 指定的金鑰簽章，**這個檔案和金鑰 `.jks` 都不在 git 裡**。

- 每次更新都必須用**同一把金鑰**，否則使用者無法直接升級，只能刪掉重裝（資料會消失）
- 請把 `.jks` 和 `key.properties` 備份到安全的地方（密碼管理器、加密的雲端硬碟）
- 沒有 `key.properties` 時，release 會改用 debug 金鑰（只適合自己測試，不要拿去發佈）

## 每次發佈的步驟

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

## 其他常用指令

| 指令 | 用途 |
|---|---|
| `gh release list` | 列出所有版本 |
| `gh release view v1.0.1` | 查看某個版本的內容 |
| `gh release upload v1.0.1 檔案.apk --clobber` | 補傳或替換某個版本的檔案 |
| `gh release edit v1.0.1 --notes-file notes.md` | 修改版本說明 |
| `gh release delete v1.0.1 --cleanup-tag` | 刪除版本（連同 git tag） |

## 更新 README 截圖

截圖使用展示模式，不會動到手機上的真實資料：

```bash
flutter run --dart-define=DEMO=true
```

截完圖後重新執行一般版本（`flutter run`），真實資料就會回來。
截圖放在 `docs/screenshots/`，寬度 480px、裁掉狀態列。
