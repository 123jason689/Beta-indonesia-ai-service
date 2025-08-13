# Prerequisites Checker for Azure AI Service Deployment
# Run this script first to ensure all required tools are installed

$ErrorActionPreference = "Continue"

Write-Host "🔍 Checking deployment prerequisites..." -ForegroundColor Cyan
Write-Host ""

$script:allGood = $true

# Check PowerShell version
Write-Host "📋 PowerShell Version:" -ForegroundColor Yellow
$psVersion = $PSVersionTable.PSVersion
Write-Host "   Version: $psVersion" -ForegroundColor White
if ($psVersion.Major -lt 5) {
    Write-Host "   ❌ PowerShell 5.0+ required" -ForegroundColor Red
    $script:allGood = $false
} else {
    Write-Host "   ✅ PowerShell version OK" -ForegroundColor Green
}
Write-Host ""

# Check Azure CLI
Write-Host "🌐 Azure CLI:" -ForegroundColor Yellow
try {
    $azResult = & az version --output json 2>$null
    if ($LASTEXITCODE -eq 0 -and $azResult) {
        $azVersion = $azResult | ConvertFrom-Json
        Write-Host "   Version: $($azVersion.'azure-cli')" -ForegroundColor White
        Write-Host "   ✅ Azure CLI is installed" -ForegroundColor Green
    } else {
        throw "Azure CLI not found"
    }
}
catch {
    Write-Host "   ❌ Azure CLI not found" -ForegroundColor Red
    Write-Host "   Install with: winget install Microsoft.AzureCLI" -ForegroundColor Yellow
    $script:allGood = $false
}
Write-Host ""

# Check Azure login status
Write-Host "🔐 Azure Authentication:" -ForegroundColor Yellow
try {
    $accountResult = & az account show --output json 2>$null
    if ($LASTEXITCODE -eq 0 -and $accountResult) {
        $account = $accountResult | ConvertFrom-Json
        Write-Host "   Account: $($account.user.name)" -ForegroundColor White
        Write-Host "   Subscription: $($account.name)" -ForegroundColor White
        Write-Host "   ✅ Logged in to Azure" -ForegroundColor Green
    } else {
        throw "Not logged in"
    }
}
catch {
    Write-Host "   ❌ Not logged in to Azure" -ForegroundColor Red
    Write-Host "   Please run: az login" -ForegroundColor Yellow
    $script:allGood = $false
}
Write-Host ""

# Check Node.js
Write-Host "📦 Node.js:" -ForegroundColor Yellow
try {
    $nodeResult = & node --version 2>$null
    if ($LASTEXITCODE -eq 0 -and $nodeResult) {
        Write-Host "   Version: $nodeResult" -ForegroundColor White
        Write-Host "   ✅ Node.js is installed" -ForegroundColor Green
    } else {
        throw "Node.js not found"
    }
}
catch {
    Write-Host "   ❌ Node.js not found" -ForegroundColor Red
    $script:allGood = $false
}
Write-Host ""

# Check Azure Functions Core Tools
Write-Host "⚡ Azure Functions Core Tools:" -ForegroundColor Yellow
try {
    $funcResult = & func --version 2>$null
    if ($LASTEXITCODE -eq 0 -and $funcResult) {
        Write-Host "   Version: $funcResult" -ForegroundColor White
        Write-Host "   ✅ Azure Functions Core Tools installed" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️ Azure Functions Core Tools not found (optional for deployment)" -ForegroundColor DarkYellow
        Write-Host "   Install with: npm install -g azure-functions-core-tools@4 --unsafe-perm true" -ForegroundColor Yellow
        # Make this optional - don't fail the check
    }
}
catch {
    Write-Host "   ⚠️ Azure Functions Core Tools not found (optional for deployment)" -ForegroundColor DarkYellow
    Write-Host "   Install with: npm install -g azure-functions-core-tools@4 --unsafe-perm true" -ForegroundColor Yellow
}
Write-Host ""

# Check Docker (optional)
Write-Host "🐳 Docker (optional):" -ForegroundColor Yellow
try {
    $dockerResult = & docker --version 2>$null
    if ($LASTEXITCODE -eq 0 -and $dockerResult) {
        Write-Host "   Version: $dockerResult" -ForegroundColor White
        Write-Host "   ✅ Docker is installed" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️ Docker not found (optional for deployment)" -ForegroundColor DarkYellow
        Write-Host "   Install from: https://www.docker.com/products/docker-desktop" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "   ⚠️ Docker not found (optional for deployment)" -ForegroundColor DarkYellow
    Write-Host "   Install from: https://www.docker.com/products/docker-desktop" -ForegroundColor Yellow
}
Write-Host ""

# Check required files
Write-Host "📁 Required Files:" -ForegroundColor Yellow
$requiredFiles = @(
    "azure-function/function_app.py",
    "azure-function/requirements.txt", 
    "azure-function/host.json",
    "container-app/processor.py",
    "container-app/Dockerfile",
    "ailibs/style_transfer.py",
    ".env"
)

foreach ($currentFile in $requiredFiles) {
    if (Test-Path $currentFile) {
        Write-Host "   ✅ $currentFile" -ForegroundColor Green
    } else {
        $missingMessage = "   ❌ " + $currentFile + " not found"
        Write-Host $missingMessage -ForegroundColor Red
        $script:allGood = $false
    }
}
Write-Host ""

# Final result
if ($script:allGood) {
    Write-Host "🎉 All prerequisites met! Ready to deploy." -ForegroundColor Green
    Write-Host ""
    Write-Host "🚀 To deploy, run:" -ForegroundColor Cyan
    Write-Host "   powershell -ExecutionPolicy Bypass -File .\deploy-azure.ps1" -ForegroundColor White
} else {
    Write-Host "❌ Some prerequisites are missing. Please install them first." -ForegroundColor Red
    Write-Host ""
    Write-Host "📋 Quick Install Commands:" -ForegroundColor Cyan
    Write-Host "   winget install Microsoft.AzureCLI" -ForegroundColor White
    Write-Host "   winget install OpenJS.NodeJS" -ForegroundColor White
    Write-Host "   npm install -g azure-functions-core-tools@4 --unsafe-perm true" -ForegroundColor White
    Write-Host "   az login" -ForegroundColor White

Write-Host ""
Read-Host -Prompt "Press Enter to continue"
