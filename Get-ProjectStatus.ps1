# Get-ProjectStatus.ps1 - Display current project status
param()

Write-Host "=== SQL Server FCI HA Project Status ===" -ForegroundColor Cyan
Write-Host ""

$projectRoot = "d:\dev2\clients\sqlserverHA"

if (-not (Test-Path $projectRoot)) {
    Write-Host "❌ Project directory not found: $projectRoot" -ForegroundColor Red
    exit 1
}

Write-Host "📁 Project Location: $projectRoot" -ForegroundColor Green
Write-Host ""

# Check directory structure
$directories = @("config", "modules", "monitoring", "logs")
Write-Host "📂 Directory Structure:" -ForegroundColor Yellow
foreach ($dir in $directories) {
    $path = Join-Path $projectRoot $dir
    if (Test-Path $path) {
        Write-Host "  ✅ $dir" -ForegroundColor Green
    } else {
        Write-Host "  ❌ $dir" -ForegroundColor Red
    }
}
Write-Host ""

# Check core files
$coreFiles = @(
    "README.md",
    "REQUIREMENTS.md", 
    "TODO.md",
    "FUTURE.md",
    "PROJECT-SUMMARY.md",
    "Start-FciDeployment.ps1",
    "config\settings.json",
    "monitoring\cloudwatch-config.json"
)

Write-Host "📄 Core Files:" -ForegroundColor Yellow
foreach ($file in $coreFiles) {
    $path = Join-Path $projectRoot $file
    if (Test-Path $path) {
        $size = (Get-Item $path).Length
        Write-Host "  ✅ $file ($size bytes)" -ForegroundColor Green
    } else {
        Write-Host "  ❌ $file" -ForegroundColor Red
    }
}
Write-Host ""

# Check PowerShell modules
$modules = @(
    "Common.psm1",
    "Aws.psm1", 
    "WindowsCluster.psm1",
    "SqlFci.psm1",
    "Monitoring.psm1",
    "Validate.psm1"
)

Write-Host "🔧 PowerShell Modules:" -ForegroundColor Yellow
foreach ($module in $modules) {
    $path = Join-Path $projectRoot "modules\$module"
    if (Test-Path $path) {
        $content = Get-Content $path -Raw
        $lines = ($content -split "`n").Count
        $functions = ($content | Select-String "function " -AllMatches).Matches.Count
        Write-Host "  ✅ $module ($lines lines, $functions functions)" -ForegroundColor Green
    } else {
        Write-Host "  ❌ $module" -ForegroundColor Red
    }
}
Write-Host ""

# Configuration validation
Write-Host "⚙️  Configuration:" -ForegroundColor Yellow
$configPath = Join-Path $projectRoot "config\settings.json"
if (Test-Path $configPath) {
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        Write-Host "  ✅ settings.json is valid JSON" -ForegroundColor Green
        Write-Host "  📋 Project Name: $($config.Project.Name)" -ForegroundColor Cyan
        Write-Host "  🌍 Region: $($config.Project.Region)" -ForegroundColor Cyan
        Write-Host "  🗄️  FCI Name: $($config.SQL.FciName)" -ForegroundColor Cyan
        Write-Host "  💾 FSx Alias: $($config.FSx.DnsAlias)" -ForegroundColor Cyan
    } catch {
        Write-Host "  ❌ settings.json has JSON errors: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "  ❌ settings.json not found" -ForegroundColor Red
}
Write-Host ""

Write-Host "🎯 Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Review and customize config\settings.json for your environment" -ForegroundColor White
Write-Host "  2. Complete remaining PowerShell module functions" -ForegroundColor White  
Write-Host "  3. Test deployment in development environment" -ForegroundColor White
Write-Host "  4. Review TODO.md for detailed implementation tasks" -ForegroundColor White
Write-Host ""

Write-Host "🚀 Ready to deploy SQL Server FCI HA!" -ForegroundColor Green
