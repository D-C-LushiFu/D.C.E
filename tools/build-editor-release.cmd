@echo off
setlocal
cd /d "%~dp0.."
set "PATH=C:\HaxeToolkit\haxe;%PATH%"
set "HAXEPATH=C:\HaxeToolkit\haxe"
set "HAXE_STD_PATH=C:\HaxeToolkit\haxe\std"
set "HXCPP_COMPILE_THREADS=4"
if /i "%~1"=="android" goto android
if not "%~1"=="" if /i not "%~1"=="windows" exit /b 2
for /f "usebackq tokens=*" %%I in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "DCE_VS=%%I"
if not defined DCE_VS exit /b 1
call "%DCE_VS%\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 1
set "HXCPP_MSVC_CUSTOM=1"
rem Reuse the validated native build cache. Distribution copies only additive files.
rem Keep app.file=DCE so existing saves and preferences use the same location.
set "DCE_MANIFEST_EXE=%CD%\export\credits-preview\windows\bin\DCE.exe"
haxelib run lime build windows -release -DofficialBuild -Dlegacy_gc_compare --app-path=export/credits-preview --app-file=DCE
exit /b %errorlevel%

:android
set "HXCPP_COMPILE_THREADS=8"
set "JAVA_HOME=D:\AndroidStudio\jbr"
set "ANDROID_SDK=D:\AndroidSDK"
set "ANDROID_NDK_ROOT=D:\AndroidSDK\ndk\21.4.7075529"
haxelib run lime build android -release -DofficialBuild --app-path=export/editor-update --app-file=DCE
exit /b %errorlevel%
