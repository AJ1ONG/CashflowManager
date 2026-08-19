# Cashflow Manager 开发工具链

这份文档用于在一台新的开发设备上复现本项目当前已验证的开发环境。

## 1. 已验证的版本

| 组件 | 版本/基线 | 用途 |
|---|---|---|
| Ubuntu | 22.04 LTS x86_64 | 当前 Linux 开发与构建环境 |
| Flutter | 3.47.0 stable | UI、测试和多平台构建 |
| Dart | 3.13.0（随 Flutter 提供） | 业务代码与命令行演练 |
| Clang | 14 | Linux 原生编译器 |
| CMake | 3.30.1 | Linux 原生构建配置 |
| Ninja | 1.10.1 | Linux 原生构建执行器 |
| GTK | 3.24.33 | Linux 桌面 UI |
| Node.js | 20+（可选） | 仅用于安装 Codex agent skills |

项目运行时依赖由 `flutter pub get` 按 `pubspec.lock` 安装。SQLite 已由
`sqlite3` Dart 包通过 Native Assets 提供，不需要单独安装 SQLite 开发包。

## 2. Ubuntu 必需系统包

```bash
sudo apt-get update
sudo apt-get install -y \
  git curl unzip xz-utils zip libglu1-mesa \
  clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
```

安装后检查：

```bash
clang++ --version
cmake --version
ninja --version
pkg-config --modversion gtk+-3.0
```

## 3. 安装隔离的 Flutter SDK

项目当前固定使用 Flutter 3.47.0。下面的安装位置与本项目已验证环境一致，
不会修改系统自带 SDK：

```bash
mkdir -p "$HOME/.local/share"
git clone --depth 1 --branch 3.47.0 \
  https://github.com/flutter/flutter.git \
  "$HOME/.local/share/flutter-sdk"
```

仅为当前终端设置命令路径：

```bash
export FLUTTER_ROOT="$HOME/.local/share/flutter-sdk"
export PATH="$FLUTTER_ROOT/bin:$PATH"
```

如果希望每次打开终端都生效，再把上面两行加入所用 shell 的配置文件；这不是
构建项目的硬性要求，也可以一直使用 Flutter 的绝对路径。

初始化 Linux 桌面支持：

```bash
flutter config --enable-linux-desktop
flutter precache --linux
flutter doctor -v
```

`flutter doctor -v` 的 Linux toolchain 一项应显示为通过。

## 4. 初始化项目

```bash
git clone <项目仓库地址> CashflowManager
cd CashflowManager
flutter pub get
```

确认 SDK 和依赖：

```bash
flutter --version
dart --version
flutter pub deps
```

## 5. 日常开发命令

```bash
# 格式化
dart format lib test bin

# 静态分析
flutter analyze

# 全量测试
flutter test

# 非 UI 端到端演练
dart run bin/non_ui_demo.dart

# 启动 Linux 桌面 UI
flutter run -d linux

# 构建 Linux release
flutter build linux --release
```

Release 可执行文件生成在：

```text
build/linux/x64/release/bundle/cashflow_manager
```

应用数据库保存在：

```text
$XDG_DATA_HOME/cashflow_manager/cashflow.sqlite
```

未设置 `XDG_DATA_HOME` 时使用：

```text
$HOME/.local/share/cashflow_manager/cashflow.sqlite
```

## 6. 常见问题

### Clang 找不到 `libclang-cpp.so.14`

Ubuntu 22.04 如果出现：

```text
clang++: error while loading shared libraries: libclang-cpp.so.14
```

先修复系统包和动态链接缓存：

```bash
sudo apt-get install --reinstall libclang-cpp14
sudo ldconfig
clang++ --version
```

如果机器上的其他开发环境覆盖了动态库搜索路径，可以只为当前终端临时加入
LLVM 14，不修改全局配置：

```bash
export LD_LIBRARY_PATH="/usr/lib/llvm-14/lib:${LD_LIBRARY_PATH:-}"
```

### 测试卡在本机 HTTP 连接

Flutter 测试进程会使用本机回环地址。如果设备配置了 HTTP 代理，执行：

```bash
export NO_PROXY="127.0.0.1,localhost"
export no_proxy="$NO_PROXY"
flutter test
```

### 清理并重新构建

```bash
flutter clean
flutter pub get
flutter build linux --release
```

## 7. 可选平台工具链

### Android

仅在需要 Android 开发时安装：

- Android Studio 或 Android SDK Command-line Tools
- Android SDK Platform、Build Tools 和 Platform Tools
- Android Emulator 或实体设备驱动

安装后执行：

```bash
flutter doctor --android-licenses
flutter doctor -v
flutter devices
```

### iOS

iOS 构建只能在 macOS 上进行，需要：

- 当前 Flutter 3.47.0 支持的 Xcode
- Xcode Command Line Tools
- CocoaPods
- iOS Simulator 或已签名实体设备

最后使用 `flutter doctor -v` 检查 Xcode 和 CocoaPods。

## 8. 可选 Codex agent skills

这部分不参与应用构建，仅用于在 Codex 中恢复本项目使用的 Flutter/Dart 技能。
需要 Node.js 20+ 和 `npx`：

```bash
npx skills add flutter/agent-plugins --skill '*' --agent universal --yes
npx skills add dart-lang/skills --skill '*' --agent universal --yes
```

安装状态记录在项目的 `skills-lock.json` 和 `.agents/skills/` 中。

## 9. 版本与许可证检查

- Dart/Flutter 依赖锁定：`pubspec.lock`
- Codex skills 锁定：`skills-lock.json`
- 运行时依赖许可证：`THIRD_PARTY_LICENSES.md`
- 产品与架构要求：`docs/PROJECT_CONTEXT.md`

升级 Flutter 或新增运行时依赖前，需要重新运行全部测试和静态分析；新增运行时
依赖还必须先检查并记录许可证。
