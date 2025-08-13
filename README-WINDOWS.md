# Windows PowerShell Deployment Guide

This guide provides step-by-step instructions for deploying the AI Style Transfer service on Azure using PowerShell on Windows.

## 🔧 Prerequisites

### Required Software:
1. **PowerShell 5.0+** (comes with Windows 10/11)
2. **Azure CLI** 
3. **Node.js** (for Azure Functions Core Tools)
4. **Azure Functions Core Tools**

### Quick Install (Windows):
```powershell
# Install Azure CLI
winget install Microsoft.AzureCLI

# Install Node.js
winget install OpenJS.NodeJS

# Install Azure Functions Core Tools (after Node.js)
npm install -g azure-functions-core-tools@4 --unsafe-perm true

# Login to Azure
az login
```

## 🚀 Deployment Steps

### Step 1: Check Prerequisites
```powershell
# Run the prerequisites checker
.\check-prerequisites.ps1
```

### Step 2: Deploy to Azure
```powershell
# Run the deployment script
.\deploy-azure.ps1
```

### Step 3: Copy the API URL
After deployment completes, copy the `VITE_AI_URL` from the output to your Frontend `.env` file.

## 📋 What the Script Does

1. **✅ Validates Prerequisites**: Checks all required tools are installed
2. **📁 Creates Resource Group**: Sets up Azure resource container
3. **💾 Creates Storage**: Sets up blob storage for images and job data
4. **🐳 Builds Container**: Creates GPU-optimized Docker container
5. **🎮 Sets up GPU Pool**: Creates spot T4 GPU instances for cost efficiency
6. **⚡ Deploys Function**: Creates serverless API endpoint
7. **🔗 Configures Integration**: Connects all components together

## 💰 Cost Optimization Features

- **Spot GPU Instances**: Up to 80% savings vs regular pricing
- **T4 GPUs**: $0.15-0.30/hour (spot) vs $1.20/hour (regular)  
- **Auto-scale to Zero**: $0 cost when idle
- **Function App**: Consumption plan (~$0 when idle)
- **Pre-cached Models**: Faster warm starts reduce billable time

## 🎯 Expected Results

After successful deployment:

```
🌐 AI Service API URL: https://beta-ai-service-api.azurewebsites.net
📝 Style Transfer Endpoint: https://beta-ai-service-api.azurewebsites.net/api/style-transfer
📈 Status Endpoint: https://beta-ai-service-api.azurewebsites.net/api/status/{job_id}

🎯 For your Frontend .env file:
VITE_AI_URL=https://beta-ai-service-api.azurewebsites.net
```

## 🧪 Testing the Deployment

### Option 1: Use the Test Client
```powershell
# Run the test client
python test_client.py
```

### Option 2: Manual API Test
```powershell
# Test with PowerShell
$body = @{
    content_image = "base64_image_data"
    style_image = "base64_image_data"
    influence = 0.7
    creativity = 0.8
} | ConvertTo-Json

$response = Invoke-RestMethod -Uri "https://beta-ai-service-api.azurewebsites.net/api/style-transfer" -Method POST -Body $body -ContentType "application/json"

Write-Host "Job ID: $($response.job_id)"
```

## ⚠️ Troubleshooting

### Common Issues:

1. **Azure CLI Not Found**:
   ```powershell
   winget install Microsoft.AzureCLI
   # Restart PowerShell after installation
   ```

2. **Not Logged in to Azure**:
   ```powershell
   az login
   # Follow browser prompts
   ```

3. **Function Deployment Failed**:
   ```powershell
   # Install Functions Core Tools
   npm install -g azure-functions-core-tools@4 --unsafe-perm true
   
   # Manually deploy function
   cd azure-function
   func azure functionapp publish beta-ai-service-api --python
   ```

4. **Resource Group Already Exists**:
   - The script will use the existing resource group
   - Ensure you have permissions in that resource group

5. **Container Build Failed**:
   - Check Docker is running (if testing locally)
   - Verify all required files are present
   - Check internet connection for downloading dependencies

### Getting Help:

1. **Check Prerequisites**: Run `.\check-prerequisites.ps1`
2. **View Logs**: Check Azure Portal for detailed error logs
3. **Resource Cleanup**: If deployment fails, clean up resources:
   ```powershell
   az group delete --name BetaResourceGroup --yes --no-wait
   ```

## 🔄 Updating the Deployment

To update your deployment:

1. **Update Code**: Make changes to your code
2. **Rebuild Container**:
   ```powershell
   az acr build --registry betaaiserviceregistry --image style-transfer-processor:latest ./container-app
   ```
3. **Redeploy Function**:
   ```powershell
   cd azure-function
   func azure functionapp publish beta-ai-service-api --python
   ```

## 📊 Monitoring Costs

Monitor your costs in the Azure Portal:
1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to "Cost Management + Billing"
3. Filter by Resource Group: "BetaResourceGroup"
4. Set up cost alerts for budget management

Expected costs:
- **Idle**: ~$0/day (everything scales to zero)
- **Light usage**: ~$5-10/month
- **Heavy usage**: Scales with actual GPU time used

---

## 🎉 Success!

Once deployed, your AI Style Transfer service will be available at the provided URL and ready to handle requests from your frontend application!
