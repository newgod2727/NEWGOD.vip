@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title PyToolbox first run
cd /d "%~dp0"

echo.
echo   PyToolbox - first run
echo   ---------------------
echo   Folder: %CD%
echo.

set "PY="

if defined TOOLBOX_PY (
  if exist "%TOOLBOX_PY%" (
    set "PY=%TOOLBOX_PY%"
    echo   Using TOOLBOX_PY override.
    goto :gotpy
  )
)

for %%V in (3.12 3.13 3.11 3) do (
  if not defined PY (
    py -%%V -c "import sys" >nul 2>&1
    if !errorlevel! equ 0 (
      for /f "usebackq delims=" %%E in (`py -%%V -c "import sys;print(sys.executable)" 2^>nul`) do set "PY=%%E"
      if defined PY echo   Found via the py launcher: -%%V
    )
  )
)

if not defined PY (
  for /f "usebackq delims=" %%P in (`where python.exe 2^>nul`) do (
    if not defined PY (
      for %%A in ("%%P") do (
        if %%~zA gtr 0 (
          set "PY=%%P"
          echo   Found on PATH: %%P
        ) else (
          echo   Skipped %%P  ^(0 bytes - that is the Microsoft Store alias, not Python^)
        )
      )
    )
  )
)

if not defined PY (
  for %%D in (
    "%LOCALAPPDATA%\Programs\Python\Python313\python.exe"
    "%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
    "%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
    "%ProgramFiles%\Python313\python.exe"
    "%ProgramFiles%\Python312\python.exe"
    "%ProgramFiles%\Python311\python.exe"
    "C:\Python313\python.exe"
    "C:\Python312\python.exe"
  ) do (
    if not defined PY if exist %%D (
      set "PY=%%~D"
      echo   Found installed at: %%~D
    )
  )
)

if not defined PY (
  for /d %%S in ("%LOCALAPPDATA%\Microsoft\WindowsApps\PythonSoftwareFoundation.Python.3*") do (
    if not defined PY if exist "%%S\python.exe" (
      set "PY=%%S\python.exe"
      echo   Found Microsoft Store Python at: %%S
    )
  )
)

if not defined PY goto :nopy

:gotpy
echo   Python: !PY!
echo.
"!PY!" "%~dp0bootstrap.py"
set "RC=!errorlevel!"
echo.
echo   bootstrap exit code: !RC!
echo   The full record is in  %~dp0FIRST-RUN.txt
echo.
echo   Press any key to close this window.
pause >nul
exit /b !RC!

:nopy
echo.
echo   ================================================================
echo   STOP - there is no Python on this machine.
echo.
echo   PyToolbox is a Python program. Nothing here can run without it.
echo.
echo   Install Python 3.12 from:
echo.
echo       https://www.python.org/downloads/windows/
echo.
echo   In the installer, tick these two boxes:
echo       [x] Add python.exe to PATH
echo       [x] tcl/tk and IDLE
echo.
echo   Then run this START.cmd again.
echo.
echo   If this is a school or work machine that blocks installers,
echo   you cannot run PyToolbox on it. That is the whole answer.
echo   ================================================================
echo.
echo   Press any key to close this window.
pause >nul
exit /b 9
