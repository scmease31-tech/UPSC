@echo off
set PATH=C:\flutter\bin;%PATH%
cd /d "c:\Users\sohil.d\Downloads\Hehe\new game"

echo === Cleaning build ===
call flutter clean
echo === Building web ===
call flutter build web --release --base-href "/UPSC/" --no-wasm-dry-run
echo === Build exit code: %ERRORLEVEL% ===
echo === Files in build\web: ===
dir /s /b build\web 2>&1 | find /c /v ""
