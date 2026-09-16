@echo off
chcp 65001 >nul
title 自动获取 DeepSeek 平台令牌
setlocal

rem 默认用本文件所在目录的 config.json；也可以把 config.json 拖到本文件上运行
set "CFG=%~dp0config.json"
if not "%~1"=="" set "CFG=%~1"
set "NODE="

rem 1) 先找 Codex 自带的 node
for /d %%D in ("%USERPROFILE%\.cache\codex-runtimes\*") do (
  if exist "%%~D\dependencies\node\bin\node.exe" set "NODE=%%~D\dependencies\node\bin\node.exe"
)
rem 2) 再找系统 PATH 里的 node
if not defined NODE (
  for %%N in (node.exe) do if not "%%~$PATH:N"=="" set "NODE=%%~$PATH:N"
)

echo ============================================================
echo   自动获取 DeepSeek 平台令牌
echo ============================================================
echo.
echo   config.json : %CFG%
echo   node        : %NODE%
echo.

if not defined NODE (
  echo [错误] 没找到 node.exe。
  echo        请先在 Codex 里跑过一次（会带上运行时），或者自己装一个 Node.js。
  echo.
  pause
  exit /b 1
)

if not exist "%CFG%" (
  if exist "%~dp0config.example.json" (
    copy /y "%~dp0config.example.json" "%CFG%" >nul
    echo [提示] 还没有 config.json，已按 config.example.json 生成一份。
    echo        记得打开它，把你的 API Key 填到 DEEPSEEK_API_KEY 里。
    echo.
  ) else (
    echo [提示] 还没有 config.json，脚本会新建一份。
    echo.
  )
)

echo   第一次运行会弹出一个浏览器窗口，请在窗口里登录
echo   https://platform.deepseek.com
echo   登录成功后脚本会自动保存令牌，以后都不用再登。
echo.
pause

"%NODE%" "%~dp0自动获取令牌.js" "%CFG%"

echo.
echo ============================================================
echo   结束。上面显示「已写入」就成功了：回到挂件，菜单里退出，再双击 start-widget.bat 重启。
echo ============================================================
echo.
pause
