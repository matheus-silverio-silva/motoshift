@echo off
setlocal

set MAVEN_VERSION=3.9.9
set MAVEN_ZIP_URL=https://downloads.apache.org/maven/maven-3/%MAVEN_VERSION%/binaries/apache-maven-%MAVEN_VERSION%-bin.zip
set MAVEN_HOME=%USERPROFILE%\.mvnw\apache-maven-%MAVEN_VERSION%

if not exist "%MAVEN_HOME%\bin\mvn.cmd" (
    echo [mvnw] Maven %MAVEN_VERSION% nao encontrado. Baixando automaticamente...
    if not exist "%USERPROFILE%\.mvnw" mkdir "%USERPROFILE%\.mvnw"
    powershell -Command "Invoke-WebRequest -Uri '%MAVEN_ZIP_URL%' -OutFile '%TEMP%\apache-maven.zip'"
    powershell -Command "Expand-Archive -Path '%TEMP%\apache-maven.zip' -DestinationPath '%USERPROFILE%\.mvnw' -Force"
    del "%TEMP%\apache-maven.zip"
    echo [mvnw] Maven instalado em %MAVEN_HOME%
)

"%MAVEN_HOME%\bin\mvn.cmd" %*
