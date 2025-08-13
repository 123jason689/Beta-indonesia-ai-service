# Serverless Style Transfer on Azure

This implementation provides a cost-efficient, serverless architecture for AI-powered style transfer that scales to zero when not in use.

## 🏗️ Architecture Overview

```
User Request → Azure Function → Azure Queue → Container App (GPU) → Result Storage
```

### Components:

1. **Azure Function** (`azure-function/`): Lightweight HTTP trigger that receives requests and queues jobs
2. **Container App** (`container-app/`): GPU-powered processor that scales from 0 to handle jobs
3. **Azure Storage**: Queue for job coordination + Blob storage for results

## 💰 Cost Benefits

- **Pay only for GPU time**: $0 when idle, only pay for seconds of actual processing
- **Auto-scaling**: Scales from 0 to multiple instances based on queue length
- **No idle costs**: Unlike VMs, you pay nothing when there are no requests

## 🚀 Deployment

### Prerequisites
- Azure CLI installed and logged in
- Docker installed
- Azure Functions Core Tools

### Quick Deploy
```bash
chmod +x deploy-azure.sh
./deploy-azure.sh
```

### Manual Deployment

1. **Deploy Azure Function**:
```bash
cd azure-function
func azure functionapp publish your-function-app --python
```

2. **Build and Deploy Container**:
```bash
cd container-app
az acr build --registry your-registry --image style-transfer-processor:latest .
az containerapp create --name style-processor --image your-registry/style-transfer-processor:latest
```

## 📡 API Usage

### Submit Style Transfer Job
```bash
POST https://your-function-app.azurewebsites.net/api/style-transfer
Content-Type: application/json

{
  "content_image": "base64_encoded_image",
  "style_image": "base64_encoded_image", 
  "influence": 0.7,
  "creativity": 0.8,
  "additional_prompt": "vibrant colors"
}
```

**Response:**
```json
{
  "job_id": "uuid",
  "status": "queued",
  "estimated_wait_time": "30-120 seconds for first request"
}
```

### Check Job Status
```bash
GET https://your-function-app.azurewebsites.net/api/status/{job_id}
```

**Response (Processing):**
```json
{
  "job_id": "uuid",
  "status": "processing"
}
```

**Response (Completed):**
```json
{
  "job_id": "uuid", 
  "status": "completed",
  "result": {
    "result_image": "base64_encoded_result",
    "processing_time": 15.3
  }
}
```

## 🧪 Testing

Use the provided test client:

```python
from test_client import StyleTransferClient

client = StyleTransferClient("https://your-function-app.azurewebsites.net")
result = client.process_style_transfer(
    content_image_path="content.jpg",
    style_image_path="style.jpg", 
    output_path="result.jpg"
)
```

## ⚡ Performance Characteristics

### Cold Start (First Request)
- **Time**: 30-120 seconds
- **Reason**: Container startup + model loading
- **Cost**: Only pay for actual processing time

### Warm Requests
- **Time**: 5-15 seconds  
- **Reason**: Container already running with models loaded
- **Cost**: Only processing time

### Auto-Shutdown
- **Trigger**: 60 seconds of no activity
- **Benefit**: Costs drop to $0 automatically

## 🔧 Configuration

### Environment Variables

**Azure Function:**
- `AZURE_STORAGE_CONNECTION_STRING`: Connection to storage account

**Container App:**
- `AZURE_STORAGE_CONNECTION_STRING`: Same storage connection
- `NUM_INFERENCE_STEPS`: AI model inference steps (default: 10)
- `MODEL_SOURCE`: "HUGGINGFACE" or "GCS"

### Scaling Configuration

The Container App automatically scales based on queue length:
- **Min replicas**: 0 (costs $0 when idle)
- **Max replicas**: 3 (adjust based on expected load)
- **Scale trigger**: 1 message in queue = 1 container instance

## 🛠️ Development

### Local Testing

1. **Run Function locally**:
```bash
cd azure-function
func start
```

2. **Run Container locally**:
```bash
cd container-app
docker build -t style-processor .
docker run --env AZURE_STORAGE_CONNECTION_STRING="..." style-processor
```

### Adding Features

- **Webhooks**: Add callback URLs to notify when jobs complete
- **Batch Processing**: Process multiple images in one request
- **Custom Models**: Upload your own style transfer models
- **Caching**: Cache popular style/content combinations

## 📊 Monitoring

Monitor your deployment through:
- **Azure Portal**: View function executions and container scaling
- **Application Insights**: Detailed performance metrics
- **Storage Metrics**: Queue length and blob usage

## 🔐 Security

- Functions use managed identity where possible
- Storage connections use connection strings (store in Key Vault for production)
- Container images are stored in private Azure Container Registry
- All communication uses HTTPS

## 🎯 Production Considerations

1. **Resource Limits**: Set appropriate CPU/memory limits for containers
2. **Error Handling**: Implement retry logic and dead letter queues
3. **Monitoring**: Set up alerts for failed jobs and long queue times
4. **Backup**: Regular backup of storage accounts
5. **Scaling**: Adjust max replicas based on expected peak load

## 💡 Cost Optimization Tips

1. **Image Compression**: Compress input images to reduce processing time
2. **Model Optimization**: Use smaller/faster models for less critical use cases
3. **Batch Processing**: Process multiple images together when possible
4. **Regional Deployment**: Deploy in regions with lower GPU costs
5. **Spot Instances**: Use spot instances for non-urgent processing (when available)

---

This serverless architecture provides the perfect balance of cost-efficiency and performance for AI workloads with sporadic usage patterns.
