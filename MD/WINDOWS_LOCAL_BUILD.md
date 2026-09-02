# Windows 本地编译 A-LLVM

本文复现 `.github/workflows/build.yml` 的 Windows `mode=build`。构建的是带 A-LLVM
overlay 的宿主 `clang.exe`，然后用它覆盖官方 NDK 中对应文件；Android sysroot、libc++、
compiler-rt 和链接器仍来自官方 NDK。

## 资源要求

- Windows 10/11 x64；
- Visual Studio，安装“使用 C++ 的桌面开发”、MSVC x64 工具集和 Windows SDK；
- Git for Windows（需要 Git Bash）、Python 3.11+、CMake 3.20+、Ninja；
- 建议 16 GB 以上内存、40 GB 以上可用磁盘空间；
- 对应版本的官方 Android NDK。NDK r29 对应 LLVM 21 overlay。

当前机器已经检测到：

```text
NDK       D:\android-ndk-r29-29.0.14206865-windows-x86_64\android-ndk-r29
LLVM      21.0.0 / base 386af4a5c64ab75eaee2448dc38f2e34a40bfed0
CMake     D:\CMake\bin\cmake.exe
Ninja     D:\AndroidSDK\Sdk\cmake\3.22.1\bin\ninja.exe
VS        D:\Microsoft Visual Studio\18\Community
Python    C:\Python312\python.exe
Git Bash  C:\Program Files\Git\bin\bash.exe
```

因此这台机器不缺必要构建组件；首次构建只需要下载精确版本的 `llvm-project` 源码。
配置阶段会提示缺少 Perl、Zlib、LibXml2 等可选组件，它们不影响当前 `clang` 与
`clang-resource-headers` 目标，无需为本项目单独安装。

## 获取精确 LLVM 源码

在普通 PowerShell 中执行。路径可调整，但不要使用其它 LLVM tag 代替 NDK 记录的
`Base revision`。

```powershell
$Repo = 'C:\Users\Administrator\Code\VScode\OLLVM\A-LLVM'
$Work = 'D:\A-LLVM-build-r29'
$Llvm = Join-Path $Work 'llvm-project'
$Base = '386af4a5c64ab75eaee2448dc38f2e34a40bfed0'

New-Item -ItemType Directory -Force -Path $Work | Out-Null
git init $Llvm
git -C $Llvm remote add origin https://github.com/llvm/llvm-project.git
git -C $Llvm fetch --depth=1 origin $Base
git -C $Llvm checkout --detach FETCH_HEAD

& 'C:\Program Files\Git\bin\bash.exe' -lc `
  'cd /c/Users/Administrator/Code/VScode/OLLVM/A-LLVM && scripts/apply_overlay.sh --llvm-src /d/A-LLVM-build-r29/llvm-project --major 21'
```

也可以先让脚本从 NDK 自动确认版本：

```powershell
python "$Repo\scripts\locate_llvm.py" `
  --ndk-dir 'D:\android-ndk-r29-29.0.14206865-windows-x86_64\android-ndk-r29' `
  --host windows-x86_64
```

## 配置与编译

打开 Visual Studio 自带的 **Developer PowerShell for VS**，确认 `Get-Command cl`
能找到 x64 MSVC，然后执行：

```powershell
$Repo = 'C:\Users\Administrator\Code\VScode\OLLVM\A-LLVM'
$Work = 'D:\A-LLVM-build-r29'
$Ninja = 'D:\AndroidSDK\Sdk\cmake\3.22.1\bin\ninja.exe'

cmake -S "$Work\llvm-project\llvm" -B "$Work\build" -G Ninja `
  "-DCMAKE_MAKE_PROGRAM=$Ninja" `
  -DCMAKE_BUILD_TYPE=Release `
  -DLLVM_ENABLE_ASSERTIONS=OFF `
  -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl `
  -DLLVM_OBFUSCATION_LINK_INTO_TOOLS=ON `
  "-DLLVM_ENABLE_PROJECTS=clang" `
  "-DLLVM_TARGETS_TO_BUILD=AArch64;ARM;X86"

cmake --build "$Work\build" --target clang clang-resource-headers --parallel 8
```

内存不足时将最后一行改成 `--parallel 4`。第一次完整构建时间取决于 CPU，构建目录通常
需要十几 GB。

## 覆盖 NDK 与验证

建议先复制一份官方 NDK 再覆盖。`overlay_ndk.sh` 还会在 prebuilt 目录创建
`bin.orig.tar`，但独立副本更便于回退。

```powershell
$Ndk = 'D:\android-ndk-r29-29.0.14206865-windows-x86_64\android-ndk-r29'
$Bash = 'C:\Program Files\Git\bin\bash.exe'

& $Bash -lc `
  'cd /c/Users/Administrator/Code/VScode/OLLVM/A-LLVM && scripts/overlay_ndk.sh --built /d/A-LLVM-build-r29/build --ndk /d/android-ndk-r29-29.0.14206865-windows-x86_64/android-ndk-r29 --host windows-x86_64 --major 21'

& $Bash -lc `
  'cd /c/Users/Administrator/Code/VScode/OLLVM/A-LLVM && tests/vmp-smoke/run.sh /d/android-ndk-r29-29.0.14206865-windows-x86_64/android-ndk-r29 windows-x86_64'
& $Bash -lc `
  'cd /c/Users/Administrator/Code/VScode/OLLVM/A-LLVM && tests/constant-enc/run.sh /d/android-ndk-r29-29.0.14206865-windows-x86_64/android-ndk-r29 windows-x86_64'
```

需要完整复现 Actions 门槛时，再依次运行 `tests/abi-smoke`、
`tests/build-system-smoke`、`tests/string-enc`、`tests/fingerprint-scrub`、
`tests/anti-tamper` 和 `tests/cert-bind` 下的脚本。

## 常见问题

- `cl` 找不到：当前终端没有加载 MSVC 环境，请使用 Developer PowerShell。
- `registration.patch` 应用失败：LLVM 源码 commit 不匹配，重新核对 NDK 的 Base revision。
- CMake 找不到 Ninja：显式传入 `-DCMAKE_MAKE_PROGRAM=<ninja.exe>`。
- 链接阶段内存不足：降低 `--parallel`；Actions 还固定 `LLVM_PARALLEL_LINK_JOBS=1`。
- 构建后的 release ELF 仍有 `.AProtect.*`：使用的是旧 clang；当前源码应改名为
  `.s0/.s1/.s2/.s3`，`tests/fingerprint-scrub` 会对此失败。

## 本机验证记录

2026-09-03 已在上述机器配置上完成：

- 精确拉取 r29 基线 `386af4a5c64ab75eaee2448dc38f2e34a40bfed0`；
- `registration.patch` 干净应用；
- `obj.Obfuscation` 全部源文件编译通过；
- `clang` / `clang-resource-headers` 完整构建通过，最终产物为
  `D:\A-LLVM-build-r29\build\bin\clang.exe`；
- 新 clang 配合官方 r29 sysroot/lld 通过 `tests/vmp-smoke` 与
  `tests/constant-enc`。
