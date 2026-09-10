# InkShelf · 墨架

本地小说阅读器（Flutter）。Android / iOS 一套代码。

## 开发环境

- Flutter SDK：`E:\flutter`（建议把 `E:\flutter\bin` 加到系统 PATH）
- 国内镜像（可选）：

```powershell
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
```

若新开终端仍提示找不到 `flutter`，先执行：

```powershell
$env:Path = "E:\flutter\bin;$env:Path"
```

## 运行 / 本地调试（Windows）

```powershell
$env:Path = "E:\flutter\bin;$env:Path"
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
cd E:\novel-reader
flutter pub get
flutter devices
flutter run -d chrome          # 最快看 UI；TTS/亮度在 Web 上能力有限
flutter run -d <androidId>     # 真机/模拟器（推荐测滑动、听书、亮度）
```

- 改代码后终端里按 `r` 热重载，`R` 热重启，`q` 退出
- 仿真翻页 / 听书 / 亮度以 **Android 或 iOS 真机** 为准
- iOS 无 Mac 时仍用 Codemagic 出包 + Sideloadly

## 当前进度

- [x] InkShelf 主题与三 Tab 骨架（书架 / 书源 / 设置）
- [x] 本地 TXT 导入、自动分章、阅读页（进度/目录/字号行距/昼夜）
- [x] 书源引擎（导入 JSON、搜索、加入书架、章节缓存）
- [x] Codemagic iOS / Android 云构建配置（`codemagic.yaml`）
- [x] 阅读三模式（左右切章 / 上下滚动 / 仿真翻页）、书签、目录搜索与回顶
- [x] 自动阅读、听书(TTS)、亮度跟随系统
- [x] 书籍详情、书源章节刷新、书架封面网格与搜索

## 阅读手势

- 点屏幕中间：显示/隐藏工具栏
- 点左侧 / 右侧：上一章或下一页（视翻页方式而定）
- **翻页方式**（阅读设置 / 设置页，默认左右切章）：
  - 左右切章：横向滑动切换章节
  - 上下滚动：纵向滑动读本章
  - 仿真翻页：章内分页左右翻，翻到头再切章
- 工具栏：目录/书签、听书、阅读设置、书籍详情、章节刷新

## 书源

- 支持粘贴 / 导入 Legado 风格 JSON（见 `sample_source.json`）
- 搜索页可跨已启用书源检索，加入书架后按章拉取并本地缓存
- App 不预置任何书源

## Codemagic 打 iOS 包（无 Mac）

工程根目录已有 [`codemagic.yaml`](codemagic.yaml)：

| Workflow | 产物 | 用途 |
|----------|------|------|
| `ios-unsigned-ipa` | `InkShelf-unsigned.ipa` | Sideloadly 装到 iPhone（云端不签名） |
| `android-release-apk` | release APK | Android 直接安装 |

### 1. 推到 GitHub

```powershell
cd E:\novel-reader
git add .
git commit -m "Add Codemagic iOS unsigned IPA workflow"
# 在 GitHub 新建私有仓库后：
git branch -M main
git remote add origin https://github.com/<你的账号>/novel-reader.git
git push -u origin main
```

### 2. 连接 Codemagic

1. 打开 [codemagic.io](https://codemagic.io)，用 GitHub 登录
2. **Applications → Add application** → 选中本仓库
3. 检测到 `codemagic.yaml` 后，选 workflow **`iOS Unsigned IPA (Sideloadly)`**
4. **Start new build**
5. 成功后在 Artifacts 下载 `InkShelf-unsigned.ipa`

默认是**手动触发**，避免每次 push 都耗免费分钟。若要 push 自动构建，编辑 `codemagic.yaml` 里注释掉的 `triggering` 段。

### 3. Sideloadly 装到 iPhone

1. Windows 安装 [Sideloadly](https://sideloadly.io)
2. 数据线连 iPhone，信任电脑
3. 拖入 IPA，登录 Apple ID → Start
4. iPhone：设置 → 通用 → VPN 与设备管理 → 信任
5. 免费签名约 **7 天**过期；代码没变可对同一 IPA 重新签名，不必重打云构建

不需要 Apple 年费开发者账号即可自用。若以后改用 TestFlight，再配付费账号与 Codemagic 自动签名即可。
