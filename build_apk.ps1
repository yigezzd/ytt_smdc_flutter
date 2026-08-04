# Flutter APK 构建脚本 - 自动重命名输出文件
# 用法: .\build_apk.ps1

Write-Host ">>> 开始构建 APK..." -ForegroundColor Cyan

# 从 pubspec.yaml 读取版本号（需在构建前解析，以便通过 dart-define 注入）
$pubspec = Get-Content "pubspec.yaml" | Select-String "^version:\s*(.+)"
if ($pubspec) {
    $rawVersion = $pubspec.Matches[0].Groups[1].Value -replace '[\r\n\s]', ''
    # 解析 version+buildNumber -> version.buildNumber（保留原始格式如 001）
    if ($rawVersion -match "^([^+]+)\+(.+)$") {
        $versionName = $Matches[1]
        $buildNumber = $Matches[2]
        $fullVersion = "$versionName.$buildNumber"
    } else {
        $fullVersion = $rawVersion
    }
} else {
    Write-Host ">>> 无法读取版本号，使用默认名称" -ForegroundColor Yellow
    $fullVersion = "unknown"
}

# 清理旧构建产物
$apkDir = "build\app\outputs\flutter-apk"
if (Test-Path $apkDir) {
    Get-ChildItem $apkDir -Filter "*.apk" | Remove-Item
    Get-ChildItem $apkDir -Filter "*.sha1" | Remove-Item
}

# 执行 Flutter 构建，拆分架构后只取 arm64-v8a APK，通过 dart-define 注入完整版本号
flutter build apk --release --split-per-abi --dart-define=FULL_VERSION=$fullVersion
if ($LASTEXITCODE -ne 0) {
    Write-Host ">>> 构建失败!" -ForegroundColor Red
    exit 1
}

# 只保留 arm64-v8a APK，其余删除
$apkDir = "build\app\outputs\flutter-apk"
$arm64Apk = Join-Path $apkDir "app-arm64-v8a-release.apk"
$newName = "ytt_smdc_flutter_$fullVersion.apk"

if (Test-Path $arm64Apk) {
    # 删除其他架构的 APK
    Get-ChildItem $apkDir -Filter "app-*-release.apk" | Where-Object { $_.Name -ne "app-arm64-v8a-release.apk" } | Remove-Item
    Get-ChildItem $apkDir -Filter "*.sha1" | Remove-Item
    # 重命名 arm64-v8a APK
    Rename-Item -Path $arm64Apk -NewName $newName
    $sizeMB = [math]::Round((Get-Item (Join-Path $apkDir $newName)).Length / 1MB, 2)
    Write-Host ">>> APK 已重命名: $newName ($sizeMB MB)" -ForegroundColor Green
    Write-Host ">>> 输出路径: $apkDir" -ForegroundColor Green
} else {
    Write-Host ">>> 未找到 app-arm64-v8a-release.apk" -ForegroundColor Red
}
