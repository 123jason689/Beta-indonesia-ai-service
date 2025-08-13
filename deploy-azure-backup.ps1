# Azure Deployment Script for Serverless GPU Style Transfer (PowerShell)
# FIXED: Uses local Docker build instead of ACR Tasks

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

Write-Host "[+] Starting Azure GPU deployment..." -ForegroundColor Green

# --- Prerequisite Checks ---
try {
    $null = az version
    Write-Host "[# --- Deployment Summary ---
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
Write-Host "• GPU Pool: Spot instances for 80% cost savings" -ForegroundColor White installed." -ForegroundColor Green
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

# --- 5. Check for existing Dockerfile and create processor if needed ---
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

# Check if requirements.txt exists, if not create a basic one for Azure libraries
if (-not (Test-Path "container-app/requirements.txt")) {
    Write-Host "[+] Creating requirements.txt for Azure integration..." -ForegroundColor Cyan
    @"
# Azure integration libraries (added to your existing requirements)
azure-storage-blob==12.19.0
azure-storage-queue==12.9.0
requests==2.31.0
python-dotenv==1.0.0
"@ | Out-File -FilePath "container-app/requirements.txt" -Encoding utf8
} else {
    Write-Host "[+] Using existing requirements.txt..." -ForegroundColor Green
}

# Use the existing multi_service_processor.py if available
if (Test-Path "container-app/multi_service_processor.py") {
    Write-Host "[+] Using existing multi_service_processor.py..." -ForegroundColor Green
    Copy-Item "container-app/multi_service_processor.py" "container-app/processor.py" -Force
} elseif (-not (Test-Path "container-app/processor.py")) {
    Write-Host "[+] Creating basic processor.py..." -ForegroundColor Cyan
    @'
import os
import sys
import json
import logging
from azure.storage.queue import QueueClient

sys.path.insert(0, "/app")
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def main():
    logger.info("Multi-service processor starting...")
    # Basic implementation - actual code will be in multi_service_processor.py
    
if __name__ == "__main__":
    main()
'@ | Out-File -FilePath "container-app/processor.py" -Encoding utf8
    Write-Host "[+] Basic processor created." -ForegroundColor Green
} else {
    Write-Host "[+] Using existing processor.py..." -ForegroundColor Green
}
    
    # Create .dockerignore for optimal build context
    @"
# Exclude models directory (will be downloaded at runtime)
models/
*.bin
*.safetensors
*.ckpt

# Python cache files
__pycache__/
*.py[cod]
*`$py.class
*.so
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
pip-wheel-metadata/
share/python-wheels/
*.egg-info/
.installed.cfg
*.egg

# Virtual environments
venv/
env/
ENV/

# IDE files
.vscode/
.idea/
*.swp
*.swo

# OS files
.DS_Store
Thumbs.db

# Azure and deployment files
azure-function/
*.ps1
*.sh

# Documentation
README.md
*.md

# Git
.git/
.gitignore

# Large databases
chroma_db/
*.sqlite3

# Logs
*.log
logs/

# Temporary files
tmp/
temp/
.tmp/
"@ | Out-File -FilePath "container-app/.dockerignore" -Encoding utf8


# --- 6. Build and Push Docker Image Locally ---
Write-Host "[+] Building and pushing container image using Docker..." -ForegroundColor Yellow

# Copy the required files to container-app for Docker build
Write-Host "[+] Preparing Docker build context for all AI services..." -ForegroundColor Cyan

# Check if we're in the correct directory
if (-not (Test-Path "ailibs")) {
    Write-Host "[-] ERROR: ailibs directory not found. Please ensure you're running this script from the AI-Services directory." -ForegroundColor Red
    exit 1
}

# Copy ailibs directory
if (Test-Path "container-app/ailibs") {
    Remove-Item -Recurse -Force "container-app/ailibs"
}
Copy-Item -Recurse "ailibs" "container-app/"

# Copy RAG directory for chromadb and cultural documents
if (Test-Path "container-app/RAG") {
    Remove-Item -Recurse -Force "container-app/RAG"
}
Copy-Item -Recurse "RAG" "container-app/"

# Copy Recommendation directory for tourism data
if (Test-Path "container-app/Recommendation") {
    Remove-Item -Recurse -Force "container-app/Recommendation"
}
Copy-Item -Recurse "Recommendation" "container-app/"

# Copy chroma_db directory if it exists
if (Test-Path "chroma_db") {
    if (Test-Path "container-app/chroma_db") {
        Remove-Item -Recurse -Force "container-app/chroma_db"
    }
    Copy-Item -Recurse "chroma_db" "container-app/"
    Write-Host "[+] Copied chroma_db to container-app/" -ForegroundColor Green
}

# Copy other required files for your Dockerfile
$filesToCopy = @("requirements.txt", ".env", "download_model.py")
foreach ($file in $filesToCopy) {
    if (Test-Path $file) {
        Copy-Item $file "container-app/" -Force
        Write-Host "[+] Copied $file to container-app/" -ForegroundColor Green
    } else {
        Write-Host "[!] Warning: $file not found, skipping..." -ForegroundColor Yellow
    }
}

# Replace the default processor with multi-service processor
if (Test-Path "container-app/multi_service_processor.py") {
    Copy-Item "container-app/multi_service_processor.py" "container-app/processor.py" -Force
    Write-Host "[+] Using multi-service processor for all AI services" -ForegroundColor Green
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
    docker build --no-cache --compress -t "$REGISTRY_SERVER/style-transfer-processor:latest" .
    
    if ($LASTEXITCODE -ne 0) {
        throw "Docker build failed"
    }
    
    # Check image size
    $imageSize = docker images "$REGISTRY_SERVER/style-transfer-processor:latest" --format "table {{.Size}}" | Select-Object -Skip 1
    Write-Host "[+] Built image size: $imageSize" -ForegroundColor Green
    
    # Push image
    Write-Host "[+] Pushing image to registry..." -ForegroundColor Cyan
    docker push "$REGISTRY_SERVER/style-transfer-processor:latest"
    
    if ($LASTEXITCODE -ne 0) {
        throw "Docker push failed"
    }
    
    Write-Host "[+] Container image pushed successfully." -ForegroundColor Green
}
finally {
    Pop-Location
}

# --- 7. Azure Batch Account with GPU Pool ---
Write-Host "[+] Checking Azure Batch account '$BATCH_ACCOUNT'..." -ForegroundColor Yellow
try {
    $batchExists = az batch account show --name $BATCH_ACCOUNT --resource-group $RESOURCE_GROUP --query "name" --output tsv 2>$null
    if ($batchExists) {
        Write-Host "[+] Batch account '$BATCH_ACCOUNT' already exists." -ForegroundColor Green
    } else {
        Write-Host "[+] Creating Azure Batch account '$BATCH_ACCOUNT'..." -ForegroundColor Cyan
        az batch account create `
            --name $BATCH_ACCOUNT `
            --resource-group $RESOURCE_GROUP `
            --location $LOCATION --only-show-errors
    }
}
catch {
    Write-Host "[-] Error with batch account: $_" -ForegroundColor Red
    exit 1
}

Write-Host "[+] Getting batch account credentials..." -ForegroundColor Yellow
$BATCH_ACCOUNT_KEY = az batch account keys list --name $BATCH_ACCOUNT --resource-group $RESOURCE_GROUP --query primary --output tsv
$BATCH_ACCOUNT_URL = "https://$BATCH_ACCOUNT.$LOCATION.batch.azure.com"

# Create GPU pool for CUDA workloads
Write-Host "[+] Setting up GPU pool for CUDA processing..." -ForegroundColor Cyan
try {
    # Set Batch account context
    az batch account set --name $BATCH_ACCOUNT --resource-group $RESOURCE_GROUP
    
    # Check if pool exists
    $poolExists = az batch pool show --pool-id $BATCH_POOL --query "id" --output tsv 2>$null
    if (-not $poolExists) {
        Write-Host "[+] Creating GPU pool with NVIDIA T4 instances..." -ForegroundColor Cyan
        
        # Create pool configuration file
        $poolConfig = @"
{
  "id": "$BATCH_POOL",
  "vmSize": "Standard_NC4as_T4_v3",
  "virtualMachineConfiguration": {
    "imageReference": {
      "publisher": "microsoft-azure-batch",
      "offer": "ubuntu-server-container",
      "sku": "20-04-lts",
      "version": "latest"
    },
    "nodeAgentSKUId": "batch.node.ubuntu 20.04",
    "containerConfiguration": {
      "type": "dockerCompatible"
    }
  },
  "targetDedicatedNodes": 0,
  "targetLowPriorityNodes": 1,
  "enableAutoScale": false,
  "maxTasksPerNode": 1
}
"@
        $poolConfig | Out-File -FilePath "pool-config.json" -Encoding utf8
        
        az batch pool create --json-file "pool-config.json"
        Remove-Item "pool-config.json" -Force
        
        Write-Host "[+] GPU pool created successfully!" -ForegroundColor Green
    } else {
        Write-Host "[+] GPU pool '$BATCH_POOL' already exists." -ForegroundColor Green
    }
}
catch {
    Write-Host "[-] Warning: Could not create GPU pool. This might be due to quota limitations." -ForegroundColor Yellow
    Write-Host "   You can create the pool manually in Azure Portal if needed." -ForegroundColor Cyan
}

# --- 8. Create Azure Function Files ---
Write-Host "[+] Checking for Azure Function files..." -ForegroundColor Yellow
if (-not (Test-Path "azure-function")) {
    Write-Host "[+] Creating azure-function directory and files..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path "azure-function" -Force
    
    # Create host.json
    @"
{
  "version": "2.0",
  "functionTimeout": "00:10:00",
  "extensions": {
    "http": {
      "routePrefix": "api"
    }
  }
}
"@ | Out-File -FilePath "azure-function/host.json" -Encoding utf8

    # Create requirements.txt for Azure Functions (Python 3.11 compatible)
    @"
azure-functions==1.18.0
azure-storage-blob==12.19.0
azure-storage-queue==12.9.0
azure-batch==14.0.0
requests==2.31.0
"@ | Out-File -FilePath "azure-function/requirements.txt" -Encoding utf8

    # Create function_app.py
    @"
import azure.functions as func
import json
import logging
import uuid
from azure.storage.queue import QueueClient
import os

app = func.FunctionApp()

@app.route(route="style-transfer", methods=["POST"])
def style_transfer(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Style transfer function processed a request.')

    try:
        # Get job data from request
        req_body = req.get_json()
        if not req_body:
            return func.HttpResponse(
                json.dumps({"error": "Request body is required"}),
                status_code=400,
                mimetype="application/json"
            )

        # Generate job ID
        job_id = str(uuid.uuid4())
        
        # Add job to queue
        connection_string = os.environ["AZURE_STORAGE_CONNECTION_STRING"]
        queue_client = QueueClient.from_connection_string(
            connection_string, 
            queue_name="style-transfer-jobs"
        )
        
        job_data = {
            "job_id": job_id,
            "content_image": req_body.get("content_image"),
            "style_image": req_body.get("style_image"),
            "strength": req_body.get("strength", 0.8)
        }
        
        queue_client.send_message(json.dumps(job_data))
        
        return func.HttpResponse(
            json.dumps({
                "job_id": job_id,
                "status": "queued",
                "message": "Style transfer job queued successfully"
            }),
            status_code=202,
            mimetype="application/json"
        )

    except Exception as e:
        logging.error(f"Error in style_transfer: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": "Internal server error"}),
            status_code=500,
            mimetype="application/json"
        )

@app.route(route="status/{job_id}", methods=["GET"])
def get_status(req: func.HttpRequest) -> func.HttpResponse:
    job_id = req.route_params.get('job_id')
    
    # For now, return a simple status
    # You would implement actual status checking here
    return func.HttpResponse(
        json.dumps({
            "job_id": job_id,
            "status": "processing",
            "message": "Job is being processed"
        }),
        mimetype="application/json"
    )
"@ | Out-File -FilePath "azure-function/function_app.py" -Encoding utf8

    Write-Host "[+] Azure Function files created successfully." -ForegroundColor Green
}

# --- 9. Azure Function App ---
Write-Host "[+] Checking Azure Function '$FUNCTION_APP'..." -ForegroundColor Yellow
try {
    $functionExists = az functionapp show --name $FUNCTION_APP --resource-group $RESOURCE_GROUP --query "name" --output tsv 2>$null
    if ($functionExists) {
        Write-Host "[+] Function app '$FUNCTION_APP' already exists." -ForegroundColor Green
    } else {
        Write-Host "[+] Creating Azure Function '$FUNCTION_APP'..." -ForegroundColor Cyan
        Push-Location "azure-function"
        try {
            az functionapp create --resource-group $RESOURCE_GROUP --os-type "Linux" --consumption-plan-location $LOCATION --runtime "python" --runtime-version "3.11" --functions-version "4" --name $FUNCTION_APP --storage-account $STORAGE_ACCOUNT --only-show-errors

            if ($LASTEXITCODE -ne 0) {
                throw "Function app creation failed"
            }
        }
        finally {
            Pop-Location
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
    "BATCH_ACCOUNT_NAME=$BATCH_ACCOUNT",
    "BATCH_ACCOUNT_KEY=$BATCH_ACCOUNT_KEY",
    "BATCH_ACCOUNT_URL=$BATCH_ACCOUNT_URL",
    "BATCH_POOL_ID=$BATCH_POOL",
    "CONTAINER_IMAGE=$REGISTRY_SERVER/style-transfer-processor:latest",
    "SCM_DO_BUILD_DURING_DEPLOYMENT=true"
)

az functionapp config appsettings set `
    --name $FUNCTION_APP `
    --resource-group $RESOURCE_GROUP `
    --settings $appSettings --only-show-errors

# Deploy function code
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

# --- Deployment Summary ---
Write-Host ""
Write-Host "[+] Deployment complete!" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "🌐 AI Service API URL: https://$FUNCTION_APP.azurewebsites.net" -ForegroundColor White
Write-Host "📝 Style Transfer Endpoint: https://$FUNCTION_APP.azurewebsites.net/api/style-transfer" -ForegroundColor White
Write-Host "📈 Status Endpoint: https://$FUNCTION_APP.azurewebsites.net/api/status/{job_id}" -ForegroundColor White
Write-Host ""
Write-Host "🎯 For your Frontend .env file:" -ForegroundColor Yellow
Write-Host "VITE_AI_URL=https://$FUNCTION_APP.azurewebsites.net" -ForegroundColor Green
Write-Host ""
Write-Host "• Cost Optimization:" -ForegroundColor Cyan
Write-Host "• Function App: Consumption plan (~`$0 when idle)" -ForegroundColor White
Write-Host "• Storage: Pay per usage" -ForegroundColor White
Write-Host "• Container Registry: Basic tier"" -ForegroundColor White