@echo off
chcp 65001 >nul
setlocal
title MotoShift
REM ==================================================================
REM  Atualiza o projeto com a versao mais recente do GitHub (main) e
REM  sobe o backend (8080) + o app Flutter web (5000).
REM  Sem internet, ou com alteracoes locais, roda o que ja esta aqui.
REM ==================================================================

cd /d "%~dp0"

REM false = o "Cheguei" do check-in vale de qualquer lugar (demo feita de casa).
REM Troque para true se quiser exigir estar perto da loja.
set "MOTOSHIFT_CHECKIN_EXIGIR_PROXIMIDADE=false"

where flutter >nul 2>&1 || (echo [ERRO] flutter nao encontrado no PATH. & pause & exit /b 1)

echo ============================================
echo  MotoShift
echo ============================================
echo.

REM ---- 1) Atualizar a partir do GitHub ----------------------------
where git >nul 2>&1 || (echo [AVISO] git nao encontrado; rodando sem atualizar. & goto sobe)

echo [1/3] Buscando a versao mais recente no GitHub...
git fetch origin --prune -q
if errorlevel 1 (
  echo [AVISO] Sem acesso ao GitHub. Rodando a versao que ja esta na maquina.
  goto versao
)

set "BRANCH="
for /f "delims=" %%b in ('git rev-parse --abbrev-ref HEAD') do set "BRANCH=%%b"
if /i not "%BRANCH%"=="main" (
  echo [AVISO] Voce esta na branch "%BRANCH%", nao na main. Rodando ela sem atualizar.
  goto versao
)

git diff --quiet HEAD
if errorlevel 1 (
  echo [AVISO] Ha alteracoes locais nao commitadas. Rodando sem atualizar para nao mexer nelas.
  goto versao
)

git pull --ff-only -q origin main
if errorlevel 1 echo [AVISO] Nao consegui atualizar a main. Rodando a versao local.

:versao
echo.
echo Versao que vai rodar:
git log -1 "--format=   %%h  %%cd  %%s" --date=format:%%d/%%m/%%Y-%%H:%%M
echo.

:sobe
REM ---- 2) Backend --------------------------------------------------
call :libera_porta 8080
call :libera_porta 5000

echo [2/3] Subindo o backend (H2 em memoria + massa de demonstracao)...
start "MotoShift BACKEND (8080)" cmd /k "cd /d "%~dp0backend" && call mvnw.cmd spring-boot:run"

echo Aguardando http://localhost:8080 (a 1a vez pode demorar alguns minutos)...
set /a TENTATIVAS=0
:espera
timeout /t 5 /nobreak >nul
set /a TENTATIVAS+=1
powershell -NoProfile -Command "try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 http://localhost:8080/swagger-ui.html | Out-Null; exit 0 } catch { if ($_.Exception.Response) { exit 0 } else { exit 1 } }"
if not errorlevel 1 goto backend_ok
if %TENTATIVAS% GEQ 120 (
  echo [ERRO] O backend nao respondeu em 10 minutos. Veja a janela "MotoShift BACKEND".
  pause
  exit /b 1
)
goto espera
:backend_ok
echo Backend no ar.
echo.

REM ---- 3) App Flutter web ------------------------------------------
echo [3/3] Subindo o app Flutter no Chrome (porta 5000)...
start "MotoShift APP (Flutter Web)" cmd /k "cd /d "%~dp0Motoshift" && flutter pub get && flutter run -d chrome --web-port=5000 --dart-define=API_URL=http://localhost:8080"

echo.
echo Tudo iniciado. O Chrome abre sozinho quando o Flutter terminar de compilar.
echo Contas de demonstracao (senha: senha123):
echo   Lojista: lojista@teste.com
echo   Motoboy: motoboy@teste.com
echo Swagger: http://localhost:8080/swagger-ui.html
echo.
echo Para encerrar, feche as janelas "MotoShift BACKEND" e "MotoShift APP".
pause
exit /b 0

REM ---- Sub-rotina: avisa e oferece encerrar quem ocupa a porta -----
:libera_porta
netstat -ano | findstr /r /c:":%1 .*LISTENING" >nul
if errorlevel 1 exit /b 0
echo [AVISO] A porta %1 ja esta em uso (talvez uma execucao anterior).
choice /c SN /m "Encerrar o processo que usa a porta %1"
if errorlevel 2 exit /b 0
for /f "tokens=5" %%p in ('netstat -ano ^| findstr /r /c:":%1 .*LISTENING"') do taskkill /PID %%p /F >nul 2>&1
timeout /t 2 /nobreak >nul
exit /b 0
