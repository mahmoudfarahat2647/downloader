# setup_android_minimal.ps1
$ErrorActionPreference = "Stop"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "1. Preparing directories in C:\Android" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

$baseDir = "C:\Android"
$jdkDir = "$baseDir\jdk-17"
$sdkDir = "$baseDir\Sdk"
$cmdlineDir = "$sdkDir\cmdline-tools\latest"
$downloadDir = "$baseDir\downloads"

New-Item -ItemType Directory -Path $baseDir -Force | Out-Null
New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null

# -----------------------------------------------------------------------------
# 2. Setup OpenJDK 17
# -----------------------------------------------------------------------------
if (-not (Test-Path "$jdkDir\bin\javac.exe")) {
    Write-Host "Downloading OpenJDK 17 (Adoptium Temurin)..." -ForegroundColor Yellow
    $jdkZip = "$downloadDir\openjdk17.zip"
    $jdkUrl = "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse"
    
    curl.exe -L -o $jdkZip $jdkUrl --progress-bar
    
    Write-Host "Extracting OpenJDK 17..." -ForegroundColor Yellow
    $jdkTemp = "$downloadDir\jdk_temp"
    if (Test-Path $jdkTemp) { Remove-Item -Recurse -Force $jdkTemp }
    tar.exe -xf $jdkZip -C $downloadDir
    
    # Find extracted folder (usually jdk-17.x.x)
    $extractedFolder = Get-ChildItem -Path $downloadDir -Directory -Filter "jdk-17*" | Select-Object -First 1
    if ($extractedFolder) {
        if (Test-Path $jdkDir) { Remove-Item -Recurse -Force $jdkDir }
        Move-Item -Path $extractedFolder.FullName -Destination $jdkDir -Force
    }
    Remove-Item -Force $jdkZip -ErrorAction SilentlyContinue
    Write-Host "OpenJDK 17 setup complete at $jdkDir" -ForegroundColor Green
} else {
    Write-Host "OpenJDK 17 already exists at $jdkDir" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 3. Setup Android Command-Line Tools
# -----------------------------------------------------------------------------
if (-not (Test-Path "$cmdlineDir\bin\sdkmanager.bat")) {
    Write-Host "Downloading Android command-line tools..." -ForegroundColor Yellow
    $cmdZip = "$downloadDir\cmdline-tools.zip"
    $cmdUrl = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
    
    curl.exe -L -o $cmdZip $cmdUrl --progress-bar
    
    Write-Host "Extracting command-line tools..." -ForegroundColor Yellow
    $cmdTemp = "$downloadDir\cmdline_temp"
    if (Test-Path $cmdTemp) { Remove-Item -Recurse -Force $cmdTemp }
    New-Item -ItemType Directory -Path $cmdTemp -Force | Out-Null
    tar.exe -xf $cmdZip -C $cmdTemp
    
    New-Item -ItemType Directory -Path "$sdkDir\cmdline-tools" -Force | Out-Null
    if (Test-Path $cmdlineDir) { Remove-Item -Recurse -Force $cmdlineDir }
    Move-Item -Path "$cmdTemp\cmdline-tools" -Destination $cmdlineDir -Force
    
    Remove-Item -Recurse -Force $cmdTemp -ErrorAction SilentlyContinue
    Remove-Item -Force $cmdZip -ErrorAction SilentlyContinue
    Write-Host "Command-line tools setup complete at $cmdlineDir" -ForegroundColor Green
} else {
    Write-Host "Command-line tools already exist at $cmdlineDir" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 4. Set Environment Variables
# -----------------------------------------------------------------------------
Write-Host "Configuring Environment Variables..." -ForegroundColor Cyan

$env:JAVA_HOME = $jdkDir
$env:ANDROID_HOME = $sdkDir
$env:ANDROID_SDK_ROOT = $sdkDir
$env:Path = "$jdkDir\bin;$cmdlineDir\bin;$sdkDir\platform-tools;C:\Users\DELL\flutter\bin;" + $env:Path

# Persist to User Environment Variables
[Environment]::SetEnvironmentVariable("JAVA_HOME", $jdkDir, [EnvironmentVariableTarget]::User)
[Environment]::SetEnvironmentVariable("ANDROID_HOME", $sdkDir, [EnvironmentVariableTarget]::User)
[Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $sdkDir, [EnvironmentVariableTarget]::User)

$userPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
$pathsToAdd = @("$jdkDir\bin", "$cmdlineDir\bin", "$sdkDir\platform-tools", "C:\Users\DELL\flutter\bin")
foreach ($p in $pathsToAdd) {
    if ($userPath -notlike "*$p*") {
        $userPath = "$p;$userPath"
    }
}
[Environment]::SetEnvironmentVariable("Path", $userPath, [EnvironmentVariableTarget]::User)

# -----------------------------------------------------------------------------
# 5. Link Android SDK with Flutter
# -----------------------------------------------------------------------------
Write-Host "Linking Android SDK with Flutter..." -ForegroundColor Cyan
& "C:\Users\DELL\flutter\bin\flutter.bat" config --android-sdk $sdkDir

# -----------------------------------------------------------------------------
# 6. Install Essential SDK packages via sdkmanager
# -----------------------------------------------------------------------------
Write-Host "Installing platform-tools, build-tools, and platform android-34..." -ForegroundColor Cyan
$sdkManager = "$cmdlineDir\bin\sdkmanager.bat"

# Accept licenses & install
$proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c echo y | `"$sdkManager`" --sdk_root=`"$sdkDir`" `"platform-tools`" `"build-tools;34.0.0`" `"platforms;android-34`"" -NoNewWindow -Wait -PassThru

Write-Host "Accepting all Android licenses..." -ForegroundColor Cyan
$licProc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c echo y | `"$sdkManager`" --sdk_root=`"$sdkDir`" --licenses" -NoNewWindow -Wait -PassThru

# Flutter accept licenses
Start-Process -FilePath "cmd.exe" -ArgumentList "/c echo y | `"C:\Users\DELL\flutter\bin\flutter.bat`" doctor --android-licenses" -NoNewWindow -Wait -PassThru

# Clean up downloads directory
Remove-Item -Recurse -Force $downloadDir -ErrorAction SilentlyContinue

Write-Host "=========================================" -ForegroundColor Green
Write-Host "Setup Completed Successfully!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
