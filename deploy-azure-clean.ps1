# Azure Deployment Script for Multi-Service AI Platform (PowerShell)
# Services: Style Transfer, RAG Chat, Tourism Recommendation

# Stop script on any error
$ErrorActionPreference = "Stop"

# --- Configuration ---
$SUBSCRIPTION_ID = "4c831c45-c701-421e-b7c1-b029d64e1e36"
az account set --subscription $SUBSCRIPTION_ID

$RESOURCE_GROUP = "BetaResourceGroup"
$LOCATION = "eastus"
$STORAGE_ACCOUNT = "betaaiservice2025"
$FUNCTION_APP = "beta-ai-service-api"
$CONTAINER_REGISTRY = "betaaiserviceregistry"
$BATCH_ACCOUNT = "beta-ai-batch"
$BATCH_POOL = "spot-gpu-pool"

Write-Host "[+] Starting Azure Multi-Service AI Platform deployment..." -ForegroundColor Green

# --- Prerequisite Checks ---
try {
    $null = az version
    Write-Host "[+] Azure CLI is installed." -ForegroundColor Green
}
catch {
    Write-Host "[-] Azure CLI is not installed. Please install it first." -ForegroundColor Red
    Write-Host "   winget install Microsoft.AzureCLI" -ForegroundColor Yellow
    exit 1
}

try {
    $null = az account show
    Write-Host "[+] Logged in to Azure." -ForegroundColor Green
}
catch {
    Write-Host "[-] Not logged in to Azure. Please run: az login" -ForegroundColor Red
    exit 1
}

# Check Docker
try {
    $null = docker --version
    Write-Host "[+] Docker is available." -ForegroundColor Green
}
catch {
    Write-Host "[-] Docker is not installed or not running. Please install Docker Desktop." -ForegroundColor Red
    Write-Host "   Download from: https://www.docker.com/products/docker-desktop" -ForegroundColor Yellow
    exit 1
}

# --- 1. Resource Group ---
Write-Host "[+] Checking resource group '$RESOURCE_GROUP'..." -ForegroundColor Yellow
if (-not (az group exists --name $RESOURCE_GROUP)) {
    Write-Host "[+] Creating resource group..." -ForegroundColor Cyan
    az group create --name $RESOURCE_GROUP --location $LOCATION
} else {
    Write-Host "[+] Resource group '$RESOURCE_GROUP' already exists." -ForegroundColor Green
}

# --- 2. Storage Account (Use Existing) ---
Write-Host "[+] Checking existing storage account '$STORAGE_ACCOUNT'..." -ForegroundColor Yellow
try {
    $storageExists = az storage account show --name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP --query "name" --output tsv 2>$null
    if ($storageExists) {
        Write-Host "[+] Using existing storage account '$STORAGE_ACCOUNT'." -ForegroundColor Green
    } else {
        Write-Host "[+] Storage account not found. Creating new storage account '$STORAGE_ACCOUNT'..." -ForegroundColor Cyan
        az storage account create `
            --name $STORAGE_ACCOUNT `
            --resource-group $RESOURCE_GROUP `
            --location $LOCATION `
            --sku "Standard_LRS" `
            --kind "StorageV2"
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[-] Failed to create storage account" -ForegroundColor Red
            exit 1
        }
        Write-Host "[+] Storage account '$STORAGE_ACCOUNT' created successfully." -ForegroundColor Green
    }
}
catch {
    Write-Host "[-] Error checking storage account: $_" -ForegroundColor Red
    exit 1
}

Write-Host "[+] Getting storage connection string..." -ForegroundColor Yellow
$STORAGE_CONNECTION_STRING = az storage account show-connection-string `
    --name $STORAGE_ACCOUNT `
    --resource-group $RESOURCE_GROUP `
    --query connectionString `
    --output tsv

# --- 3. Storage Queues and Containers for All Services ---
Write-Host "[+] Creating storage queues and blob containers for all AI services..." -ForegroundColor Yellow
az storage queue create --name "style-transfer-jobs" --connection-string $STORAGE_CONNECTION_STRING --only-show-errors
az storage queue create --name "rag-jobs" --connection-string $STORAGE_CONNECTION_STRING --only-show-errors
az storage queue create --name "recommendation-jobs" --connection-string $STORAGE_CONNECTION_STRING --only-show-errors
az storage container create --name "ai-service-results" --connection-string $STORAGE_CONNECTION_STRING --public-access blob --only-show-errors

# --- 4. Container Registry (ACR) ---
Write-Host "[+] Checking container registry '$CONTAINER_REGISTRY'..." -ForegroundColor Yellow
try {
    $registryExists = az acr show --name $CONTAINER_REGISTRY --resource-group $RESOURCE_GROUP --query "name" --output tsv 2>$null
    if ($registryExists) {
        Write-Host "[+] Container registry '$CONTAINER_REGISTRY' already exists." -ForegroundColor Green
    } else {
        Write-Host "[+] Creating container registry '$CONTAINER_REGISTRY'..." -ForegroundColor Cyan
        az acr create `
            --resource-group $RESOURCE_GROUP `
            --name $CONTAINER_REGISTRY `
            --sku "Basic" `
            --admin-enabled true --only-show-errors
    }
}
catch {
    Write-Host "[-] Error with container registry: $_" -ForegroundColor Red
    exit 1
}

Write-Host "[+] Getting registry credentials..." -ForegroundColor Yellow
$REGISTRY_SERVER = az acr show --name $CONTAINER_REGISTRY --resource-group $RESOURCE_GROUP --query loginServer --output tsv
$REGISTRY_USERNAME = az acr credential show --name $CONTAINER_REGISTRY --resource-group $RESOURCE_GROUP --query username --output tsv
$REGISTRY_PASSWORD = az acr credential show --name $CONTAINER_REGISTRY --resource-group $RESOURCE_GROUP --query "passwords[0].value" --output tsv

# --- 5. Check for existing container files ---
Write-Host "[+] Checking for container files..." -ForegroundColor Yellow
if (-not (Test-Path "container-app")) {
    New-Item -ItemType Directory -Path "container-app" -Force
}

# Check if Dockerfile already exists
if (Test-Path "container-app/Dockerfile") {
    Write-Host "[+] Using existing Dockerfile with CUDA and Python 3.12.4..." -ForegroundColor Green
} else {
    Write-Host "[-] ERROR: Dockerfile not found in container-app directory." -ForegroundColor Red
    Write-Host "   Please ensure your Dockerfile is located at: container-app/Dockerfile" -ForegroundColor Yellow
    exit 1
}

# Use the existing multi_service_processor.py if available
if (Test-Path "container-app/multi_service_processor.py") {
    Write-Host "[+] Using existing multi_service_processor.py..." -ForegroundColor Green
} else {
    Write-Host "[!] Warning: multi_service_processor.py not found. Using basic processor..." -ForegroundColor Yellow
}

# --- 6. Build and Push Docker Image Locally ---
Write-Host "[+] Building and pushing container image using Docker..." -ForegroundColor Yellow

# Copy the required files and directories to container-app for Docker build
Write-Host "[+] Preparing Docker build context for all AI services..." -ForegroundColor Cyan

# Check if we're in the correct directory
if (-not (Test-Path "ailibs")) {
    Write-Host "[-] ERROR: ailibs directory not found. Please ensure you're running this script from the AI-Services directory." -ForegroundColor Red
    exit 1
}

# Copy essential directories for all services
$directoriesToCopy = @("ailibs", "RAG", "Recommendation")
foreach ($dir in $directoriesToCopy) {
    if (Test-Path $dir) {
        if (Test-Path "container-app/$dir") {
            Remove-Item -Recurse -Force "container-app/$dir"
        }
        Copy-Item -Recurse $dir "container-app/" -Force
        Write-Host "[+] Copied $dir/ to container-app/" -ForegroundColor Green
    } else {
        Write-Host "[!] Warning: $dir directory not found, skipping..." -ForegroundColor Yellow
    }
}

# Copy ChromaDB if it exists
if (Test-Path "chroma_db") {
    if (Test-Path "container-app/chroma_db") {
        Remove-Item -Recurse -Force "container-app/chroma_db"
    }
    Copy-Item -Recurse "chroma_db" "container-app/" -Force
    Write-Host "[+] Copied chroma_db/ to container-app/" -ForegroundColor Green
}

# Copy other required files
$filesToCopy = @("requirements.txt", ".env", "download_model.py")
foreach ($file in $filesToCopy) {
    if (Test-Path $file) {
        Copy-Item $file "container-app/" -Force
        Write-Host "[+] Copied $file to container-app/" -ForegroundColor Green
    } else {
        Write-Host "[!] Warning: $file not found, skipping..." -ForegroundColor Yellow
    }
}

Push-Location "container-app"
try {
    # Login to ACR
    Write-Host "[+] Logging into Azure Container Registry..." -ForegroundColor Cyan
    $REGISTRY_PASSWORD | docker login $REGISTRY_SERVER --username $REGISTRY_USERNAME --password-stdin
    
    if ($LASTEXITCODE -ne 0) {
        throw "Docker login failed"
    }
    
    # Build image with GPU support and optimized settings
    Write-Host "[+] Building Docker image with CUDA and Python 3.12.4 support..." -ForegroundColor Cyan
    docker build --no-cache --compress -t "$REGISTRY_SERVER/multi-ai-processor:latest" .
    
    if ($LASTEXITCODE -ne 0) {
        throw "Docker build failed"
    }
    
    # Check image size
    $imageSize = docker images "$REGISTRY_SERVER/multi-ai-processor:latest" --format "table {{.Size}}" | Select-Object -Skip 1
    Write-Host "[+] Built image size: $imageSize" -ForegroundColor Green
    
    # Push image
    Write-Host "[+] Pushing image to registry..." -ForegroundColor Cyan
    docker push "$REGISTRY_SERVER/multi-ai-processor:latest"
    
    if ($LASTEXITCODE -ne 0) {
        throw "Docker push failed"
    }
    
    Write-Host "[+] Container image pushed successfully." -ForegroundColor Green
}
finally {
    Pop-Location
}

# --- 7. Azure Function App ---
Write-Host "[+] Checking Azure Function '$FUNCTION_APP'..." -ForegroundColor Yellow
try {
    $functionExists = az functionapp show --name $FUNCTION_APP --resource-group $RESOURCE_GROUP --query "name" --output tsv 2>$null
    if ($functionExists) {
        Write-Host "[+] Function app '$FUNCTION_APP' already exists." -ForegroundColor Green
    } else {
        Write-Host "[+] Creating Azure Function '$FUNCTION_APP'..." -ForegroundColor Cyan
        az functionapp create --resource-group $RESOURCE_GROUP --os-type "Linux" --consumption-plan-location $LOCATION --runtime "python" --runtime-version "3.11" --functions-version "4" --name $FUNCTION_APP --storage-account $STORAGE_ACCOUNT --only-show-errors

        if ($LASTEXITCODE -ne 0) {
            throw "Function app creation failed"
        }
    }
}
catch {
    Write-Host "[-] Error with function app: $_" -ForegroundColor Red
    exit 1
}

# Configure Function App settings
Write-Host "[+] Configuring Function App settings..." -ForegroundColor Yellow
$appSettings = @(
    "AZURE_STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION_STRING",
    "CONTAINER_IMAGE=$REGISTRY_SERVER/multi-ai-processor:latest",
    "SCM_DO_BUILD_DURING_DEPLOYMENT=true"
)

az functionapp config appsettings set `
    --name $FUNCTION_APP `
    --resource-group $RESOURCE_GROUP `
    --settings $appSettings --only-show-errors

# Deploy function code
if (Test-Path "azure-function") {
    if (Get-Command func -ErrorAction SilentlyContinue) {
        Write-Host "[+] Deploying function code..." -ForegroundColor Cyan
        Push-Location "azure-function"
        try {
            func azure functionapp publish $FUNCTION_APP --python
        }
        finally {
            Pop-Location
        }
    } else {
        Write-Host "[-] WARNING: Azure Functions Core Tools not found. Skipping code deployment." -ForegroundColor Yellow
        Write-Host "   Install with: npm install -g azure-functions-core-tools@4 --unsafe-perm true" -ForegroundColor Cyan
    }
} else {
    Write-Host "[!] Warning: azure-function directory not found." -ForegroundColor Yellow
}

# --- Deployment Summary ---
Write-Host ""
Write-Host "[+] Deployment complete!" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "🌐 AI Service API URL: https://$FUNCTION_APP.azurewebsites.net" -ForegroundColor White
Write-Host ""
Write-Host "📝 API Endpoints:" -ForegroundColor Yellow
Write-Host "• Style Transfer: https://$FUNCTION_APP.azurewebsites.net/api/style-transfer" -ForegroundColor White
Write-Host "• RAG Chat (Arunika): https://$FUNCTION_APP.azurewebsites.net/api/rag-chat" -ForegroundColor White
Write-Host "• Tourism Recommendation: https://$FUNCTION_APP.azurewebsites.net/api/recommendation" -ForegroundColor White
Write-Host "• Job Status: https://$FUNCTION_APP.azurewebsites.net/api/status/{job_id}" -ForegroundColor White
Write-Host "• Health Check: https://$FUNCTION_APP.azurewebsites.net/api/health" -ForegroundColor White
Write-Host ""
Write-Host "🎯 For your Frontend .env file:" -ForegroundColor Yellow
Write-Host "VITE_AI_URL=https://$FUNCTION_APP.azurewebsites.net" -ForegroundColor Green
Write-Host ""
Write-Host "🎮 Services Available:" -ForegroundColor Cyan
Write-Host "• 🎨 Style Transfer: AI image style transfer with SD v1.5 + ControlNet + IP-Adapter" -ForegroundColor White
Write-Host "• 🤖 RAG Chat: Cultural chatbot Arunika with ChromaDB + Ollama" -ForegroundColor White
Write-Host "• 📍 Tourism Recommendation: Personalized tourism suggestions" -ForegroundColor White
Write-Host ""
Write-Host "💰 Cost Optimization:" -ForegroundColor Cyan
Write-Host "• Function App: Consumption plan (~`$0 when idle)" -ForegroundColor White
Write-Host "• Container Processing: Auto-shutdown after 2 minutes idle" -ForegroundColor White
Write-Host "• Storage: Pay per usage" -ForegroundColor White
Write-Host "• Multi-service efficiency: One container handles all AI workloads" -ForegroundColor White
