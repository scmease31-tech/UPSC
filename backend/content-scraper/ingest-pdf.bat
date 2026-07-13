@echo off
REM ============================================================================
REM  UPSC PDF Ingest - Windows runner
REM
REM  Usage:
REM    ingest-pdf.bat "C:\path\to\Daily Vocabulary 13-07-2026.pdf" vocabulary
REM    ingest-pdf.bat "C:\path\to\IE Delhi 13-07-2026.pdf" newspaper "Indian Express"
REM    ingest-pdf.bat "C:\path\to\editorials.pdf" editorial
REM
REM  Credentials: point GOOGLE_APPLICATION_CREDENTIALS at your Firebase Admin
REM  service-account JSON. If it is already set in your environment, that value
REM  is used. Otherwise the default path below is used - edit if yours differs.
REM ============================================================================

setlocal

REM Auto-detect the newest Firebase Admin key in Downloads if not already set.
if not defined GOOGLE_APPLICATION_CREDENTIALS (
  for /f "delims=" %%F in ('dir /b /a-d /o-d "%USERPROFILE%\Downloads\*firebase-adminsdk*.json" 2^>nul') do (
    if not defined GOOGLE_APPLICATION_CREDENTIALS set "GOOGLE_APPLICATION_CREDENTIALS=%USERPROFILE%\Downloads\%%F"
  )
)

if not defined GOOGLE_APPLICATION_CREDENTIALS (
  echo [ERROR] No Firebase Admin service-account JSON found in %USERPROFILE%\Downloads.
  echo Download one from Firebase Console ^> Project Settings ^> Service accounts,
  echo or set GOOGLE_APPLICATION_CREDENTIALS to its path, then retry.
  exit /b 1
)

if not exist "%GOOGLE_APPLICATION_CREDENTIALS%" (
  echo [ERROR] Service account key not found at:
  echo         %GOOGLE_APPLICATION_CREDENTIALS%
  echo Set GOOGLE_APPLICATION_CREDENTIALS to your Firebase Admin JSON and retry.
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
