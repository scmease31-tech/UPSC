@echo off
REM ============================================================================
REM  UPSC PDF Ingest - Windows runner (single file)
REM
REM  Usage:
REM    ingest-pdf.bat "C:\path\to\Daily Vocabulary 14-07-2026.pdf" vocabulary
REM    ingest-pdf.bat "C:\path\to\IE Delhi 14-07-2026.pdf" newspaper "Indian Express"
REM    ingest-pdf.bat "C:\path\to\editorials.pdf" editorial
REM
REM  Credentials: auto-detected from Downloads / the project folder, or set
REM  GOOGLE_APPLICATION_CREDENTIALS to your Firebase Admin JSON path.
REM ============================================================================

setlocal

if not defined GOOGLE_APPLICATION_CREDENTIALS call :findkey "%USERPROFILE%\Downloads"
if not defined GOOGLE_APPLICATION_CREDENTIALS call :findkey "%~dp0..\.."
if not defined GOOGLE_APPLICATION_CREDENTIALS call :findkey "%~dp0."

if not defined GOOGLE_APPLICATION_CREDENTIALS (
  echo [ERROR] No Firebase Admin service-account JSON found in Downloads or the project folder.
  echo Put your Firebase Admin JSON in Downloads, or set GOOGLE_APPLICATION_CREDENTIALS, then retry.
  exit /b 1
)

if "%~1"=="" (
  echo Usage: ingest-pdf.bat "path\to\file.pdf" ^<vocabulary^|newspaper^|editorial^> [source]
  exit /b 1
)

set "PDF=%~1"
set "TYPE=%~2"
if "%TYPE%"=="" set "TYPE=vocabulary"

set "SOURCE_ARG="
if not "%~3"=="" set "SOURCE_ARG=--source "%~3""

echo Using credentials: %GOOGLE_APPLICATION_CREDENTIALS%
node "%~dp0pdf-ingest.js" "%PDF%" --type %TYPE% %SOURCE_ARG%

endlocal
exit /b 0

:findkey
for /f "delims=" %%F in ('dir /b /a-d /o-d "%~1\*firebase-adminsdk*.json" 2^>nul') do (
  if not defined GOOGLE_APPLICATION_CREDENTIALS set "GOOGLE_APPLICATION_CREDENTIALS=%~1\%%F"
)
goto :eof
