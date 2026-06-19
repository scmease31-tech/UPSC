@echo off
REM ==========================================
REM Batch processor: runs fix_books.js in batches of 3
REM Automatically restarts after each batch to prevent OOM
REM ==========================================
setlocal enabledelayedexpansion

set NODE="C:\Program Files\nodejs\node.exe"
set SCRIPT=fix_books.js
set BATCH_SIZE=3
set MAX_RUNS=15

echo ═══════════════════════════════════════════════
echo   UPSC Books - Batch OCR Processor
echo   Processing %BATCH_SIZE% books per run, %MAX_RUNS% max runs
echo ═══════════════════════════════════════════════

for /L %%i in (1,1,%MAX_RUNS%) do (
    echo.
    echo ═══ Run %%i of %MAX_RUNS% ═══
    %NODE% --max-old-space-size=2048 --expose-gc %SCRIPT% --batch %BATCH_SIZE%
    if errorlevel 1 (
        echo Run %%i exited with error, continuing...
        timeout /t 5 /nobreak >nul
    )
    echo Run %%i complete, restarting for next batch...
    timeout /t 3 /nobreak >nul
)

echo.
echo ═══════════════════════════════════════════════
echo   All runs complete!
echo ═══════════════════════════════════════════════
