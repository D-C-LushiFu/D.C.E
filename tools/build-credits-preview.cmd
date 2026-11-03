@echo off
setlocal
cd /d "%~dp0.."
for /f "usebackq tokens=*" %%I in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "DCE_VS=%%I"
if not defined DCE_VS (
  echo Visual Studio C++ build tools were not found.
  exit /b 1
)
call "%DCE_VS%\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 1
set "PATH=C:\HaxeToolkit\haxe;%PATH%"
set "HAXEPATH=C:\HaxeToolkit\haxe"
set "HAXE_STD_PATH=C:\HaxeToolkit\haxe\std"
rem hxcpp's older auto-detection can overwrite the environment from Visual Studio 18.
set "HXCPP_MSVC_CUSTOM=1"
if /i "%~1"=="native" goto native
rem Use the installed desktop hxcpp runtime and keep the preview in its own output folder.
haxelib run lime build windows -release -Dlegacy_gc_compare --app-path=export/credits-preview --app-file=DCE
exit /b %errorlevel%

:native
pushd export\credits-preview\windows\obj
haxelib run hxcpp Build.xml haxe -DHXCPP_MSVC_CUSTOM=1
if errorlevel 1 exit /b 1
popd
copy /y export\credits-preview\windows\obj\ApplicationMain.exe export\credits-preview\windows\bin\DCE.exe >nul
if errorlevel 1 exit /b 1
mt.exe -nologo -manifest windows\DCE.manifest -outputresource:export\credits-preview\windows\bin\DCE.exe;1
exit /b %errorlevel%
