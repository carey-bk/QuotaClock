# QuotaClock

[English](../README.md) · [简体中文](README.zh-Hans.md) · **繁體中文**

**AI 額度，一眼掌握。** 在 macOS 選單列、桌面小工具與螢幕保護程式中查看 AI 服務的剩餘額度與餘額。

[官網](https://carey-bk.github.io/QuotaClock/) · [下載最新版](https://github.com/carey-bk/QuotaClock/releases/latest) · [技術文件（英文）](README.md)

## 主要功能

- 支援 Codex 多帳號、Claude 訂閱及受支援的 CLI/API 服務。
- 整合固定版本的 CodexBar 引擎，提供 100 個可選接入 ID。這不代表 100 家服務都經過真實帳號驗證；每個入口需要對應的登入狀態或憑證。
- Claude 可選擇 Desktop 或 Code CLI 登入來源讀取訂閱額度。Token 統計僅讀取本機可用的 **Code 記錄**，區分 Desktop 關聯記錄與 CLI／其他記錄，**不包含一般 Desktop Chat**。
- 三種尺寸的小工具、選單列面板與螢幕保護程式；支援主題、圖示、排序、各入口顯示控制與 Auto Hero。
- 可儲存並切換 Codex 帳號。切換會中斷執行中的工作，請先完成目前的任務。
- 預設每天自動檢查更新；發現更新後顯示於設定首頁，並在選單列面板的設定按鈕上顯示紅點。背景檢查不彈出視窗，確認後才下載。

## 安裝與更新

需要 macOS 14 或更新版本，支援 Apple Silicon 與 Intel。正式發行套件使用 Developer ID 簽署並通過 Apple 公證。

1. 下載 DMG，將 QuotaClock 拖入 Applications，然後完成應用程式內的引導。
2. 透過 macOS「編輯小工具」加入桌面小工具。
3. 需要螢幕保護程式時，按兩下 `QuotaClock.saver` 安裝，再到系統設定中選用。
4. 在「一般 → 軟體更新」、關於頁或應用程式選單手動檢查更新；自動檢查可以關閉。

應用程式更新包含小工具；獨立螢幕保護程式需要透過「關於 → 安裝或更新螢幕保護程式」另外更新。0.x 版本需要先手動升級一次。

## 資料範圍

主應用程式擷取資料，其他顯示入口讀取本地快照。獨立登入憑證儲存在 macOS 鑰匙圈中。缺失或過期的資料會明確標示，不會產生虛假額度。桌面小工具的重新整理時機由 macOS 決定。

Claude 本地 Token 總量可能包含本機過去切換過的帳號，並非目前訂閱的完整用量。7 天長條圖統計截至昨天的 7 個完整本地日曆日；當天的 Code 用量會先計入總量。沒有記錄時顯示無法取得，不視為零。

QuotaClock 並非 OpenAI、Anthropic 或其他服務商的官方產品。儲存庫目前未授予整體專案的開放原始碼授權。建置、第三方授權與接入細節請參閱[英文文件](README.md)。
