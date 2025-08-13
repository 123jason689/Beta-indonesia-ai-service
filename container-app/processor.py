import os
import json
import base64
import time
import logging
import sys
from datetime import datetime
from azure.storage.blob import BlobServiceClient

# Import your existing style transfer module
sys.path.append('/app')
from ailibs.style_transfer import style_trans, model_load

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Azure Storage configuration
STORAGE_CONNECTION_STRING = os.environ.get('AZURE_STORAGE_CONNECTION_STRING')
BLOB_CONTAINER = "style-transfer-results"

class StyleTransferProcessor:
    def __init__(self, job_id):
        self.job_id = job_id
        self.blob_service_client = BlobServiceClient.from_connection_string(
            STORAGE_CONNECTION_STRING
        )
        self.model_loaded = False
        
        # Ensure blob container exists
        try:
            self.blob_service_client.create_container(BLOB_CONTAINER)
        except Exception:
            pass  # Container might already exist
    
    def load_model_if_needed(self):
        """Load the AI model if not already loaded"""
        if not self.model_loaded:
            logger.info("Loading AI model (SD v1.5 + ControlNet + IP-Adapter)...")
            try:
                model_load()
                self.model_loaded = True
                logger.info("✅ AI model loaded successfully!")
            except Exception as e:
                logger.error(f"❌ Failed to load AI model: {e}")
                raise
    
    def get_job_data(self):
        """Retrieve job data from blob storage"""
        try:
            blob_client = self.blob_service_client.get_blob_client(
                container=BLOB_CONTAINER,
                blob=f"{self.job_id}/input.json"
            )
            job_data_str = blob_client.download_blob().readall().decode()
            return json.loads(job_data_str)
        except Exception as e:
            logger.error(f"Failed to get job data: {e}")
            raise
    
    def process_job(self):
        """Process a single style transfer job"""
        try:
            # Get job data
            job_data = self.get_job_data()
            
            logger.info(f"Processing job {self.job_id}")
            logger.info(f"Job params: influence={job_data.get('influence', 0.7)}, creativity={job_data.get('creativity', 0.8)}")
            
            # Load model if needed (only on first job)
            self.load_model_if_needed()
            
            # Perform style transfer
            start_time = time.time()
            
            result_image = style_trans(
                content_image_b64=job_data['content_image'],
                style_image_b64=job_data['style_image'],
                influence=job_data.get('influence', 0.7),
                creativity=job_data.get('creativity', 0.8),
                additional_prompt=job_data.get('additional_prompt', '')
            )
            
            processing_time = time.time() - start_time
            
            # Convert result image to base64
            from io import BytesIO
            buffered = BytesIO()
            result_image.save(buffered, format="PNG")
            result_base64 = base64.b64encode(buffered.getvalue()).decode()
            
            # Prepare result
            result_data = {
                "job_id": self.job_id,
                "status": "completed",
                "result_image": result_base64,
                "processing_time": processing_time,
                "completed_at": datetime.utcnow().isoformat(),
                "metadata": {
                    "influence": job_data.get('influence', 0.7),
                    "creativity": job_data.get('creativity', 0.8),
                    "additional_prompt": job_data.get('additional_prompt', ''),
                    "gpu_used": "T4 (16GB VRAM)",
                    "models": "SD v1.5 + ControlNet + IP-Adapter"
                }
            }
            
            # Save result to blob storage
            blob_client = self.blob_service_client.get_blob_client(
                container=BLOB_CONTAINER,
                blob=f"{self.job_id}/result.json"
            )
            blob_client.upload_blob(
                json.dumps(result_data), 
                overwrite=True
            )
            
            logger.info(f"✅ Job {self.job_id} completed in {processing_time:.2f} seconds")
            
            # If there's a callback URL, you could send a webhook here
            callback_url = job_data.get('callback_url')
            if callback_url:
                # TODO: Implement webhook notification
                logger.info(f"Callback URL provided: {callback_url}")
            
            return True
            
        except Exception as e:
            logger.error(f"❌ Error processing job: {e}")
            import traceback
            logger.error(traceback.format_exc())
            
            # Save error result
            try:
                error_result = {
                    "job_id": self.job_id,
                    "status": "failed",
                    "error": str(e),
                    "failed_at": datetime.utcnow().isoformat()
                }
                
                blob_client = self.blob_service_client.get_blob_client(
                    container=BLOB_CONTAINER,
                    blob=f"{self.job_id}/result.json"
                )
                blob_client.upload_blob(
                    json.dumps(error_result), 
                    overwrite=True
                )
                
            except Exception as save_error:
                logger.error(f"Failed to save error result: {save_error}")
            
            return False

def main():
    """Entry point for the container"""
    if len(sys.argv) != 2:
        logger.error("Usage: python processor.py <job_id>")
        sys.exit(1)
    
    job_id = sys.argv[1]
    logger.info(f"🚀 Style Transfer Processor starting for job {job_id}...")
    
    processor = StyleTransferProcessor(job_id)
    success = processor.process_job()
    
    if success:
        logger.info("� Style Transfer Processor completed successfully")
        sys.exit(0)
    else:
        logger.error("❌ Style Transfer Processor failed")
        sys.exit(1)

if __name__ == "__main__":
    main()
