@echo off
chcp 65001 >nul
title MotoShift - Apresentacao
REM Sobe backend (8080) e app Flutter web (5000) a partir desta pasta.

set "PROJ=%~dp0."

if not exist "%PROJ%\backend\pom.xml" (
  echo Nao encontrei o backend em "%PROJ%".
  pause
  exit /b 1
)

echo ============================================
echo  MotoShift - subindo backend e app (web)
echo  Projeto: %PROJ%
echo ============================================
echo.

REM 1) Backend Spring Boot (H2 em memoria + massa de demonstracao) na porta 8080
start "MotoShift BACKEND (8080)" cmd /k "cd /d "%PROJ%\backend" && call mvnw.cmd spring-boot:run"

echo Aguardando o backend responder em http://localhost:8080 ...
:espera
timeout /t 5 /nobreak >nul
powershell -NoProfile -Command "try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 http://localhost:8080/swagger-ui.html | Out-Null; exit 0 } catch { if ($_.Exception.Response) { exit 0 } else { exit 1 } }"
if errorlevel 1 goto espera
echo Backend no ar.
echo.

REM 2) App Flutter no Chrome, porta fixa 5000
start "MotoShift APP (Flutter Web)" cmd /k "cd /d "%PROJ%\Motoshift" && flutter pub get && flutter run -d chrome --web-port=5000"

echo.
echo Tudo iniciado. O Chrome abre sozinho quando o Flutter terminar de compilar.
echo Contas de demonstracao (senha: senha123):
echo   Lojista: lojista@teste.com
echo   Motoboy: motoboy@teste.com
echo.
echo Para encerrar, feche as janelas "MotoShift BACKEND" e "MotoShift APP".
pause
