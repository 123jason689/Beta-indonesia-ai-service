import requests
import base64
import time
import json
from PIL import Image
from io import BytesIO

class StyleTransferClient:
    def __init__(self, api_url):
        self.api_url = api_url.rstrip('/')
    
    def encode_image_to_base64(self, image_path):
        """Convert image file to base64 string"""
        with open(image_path, "rb") as image_file:
            return base64.b64encode(image_file.read()).decode()
    
    def decode_base64_to_image(self, base64_string):
        """Convert base64 string back to PIL Image"""
        image_data = base64.b64decode(base64_string)
        return Image.open(BytesIO(image_data))
    
    def submit_style_transfer(self, content_image_path, style_image_path, 
                            influence=0.7, creativity=0.8, additional_prompt=""):
        """Submit a style transfer job"""
        
        # Encode images to base64
        content_b64 = self.encode_image_to_base64(content_image_path)
        style_b64 = self.encode_image_to_base64(style_image_path)
        
        # Prepare request
        payload = {
            "content_image": content_b64,
            "style_image": style_b64,
            "influence": influence,
            "creativity": creativity,
            "additional_prompt": additional_prompt
        }
        
        # Submit job
        response = requests.post(f"{self.api_url}/api/style-transfer", json=payload)
        
        if response.status_code == 202:
            return response.json()
        else:
            raise Exception(f"Failed to submit job: {response.text}")
    
    def check_status(self, job_id):
        """Check the status of a job"""
        response = requests.get(f"{self.api_url}/api/status/{job_id}")
        
        if response.status_code == 200:
            return response.json()
        else:
            raise Exception(f"Failed to check status: {response.text}")
    
    def wait_for_completion(self, job_id, max_wait_time=300, poll_interval=5):
        """Wait for job completion and return the result"""
        start_time = time.time()
        
        while time.time() - start_time < max_wait_time:
            status_response = self.check_status(job_id)
            
            if status_response["status"] == "completed":
                return status_response["result"]
            elif status_response["status"] == "failed":
                raise Exception(f"Job failed: {status_response.get('error', 'Unknown error')}")
            
            print(f"Job {job_id} status: {status_response['status']}")
            time.sleep(poll_interval)
        
        raise TimeoutError(f"Job {job_id} did not complete within {max_wait_time} seconds")
    
    def process_style_transfer(self, content_image_path, style_image_path, 
                             output_path, influence=0.7, creativity=0.8, 
                             additional_prompt=""):
        """Complete style transfer process: submit job, wait for completion, save result"""
        
        print("🎨 Submitting style transfer job...")
        job_response = self.submit_style_transfer(
            content_image_path, style_image_path, 
            influence, creativity, additional_prompt
        )
        
        job_id = job_response["job_id"]
        print(f"✅ Job submitted with ID: {job_id}")
        print(f"⏱️ {job_response['message']}")
        
        print("⏳ Waiting for completion...")
        result = self.wait_for_completion(job_id)
        
        # Save result image
        result_image = self.decode_base64_to_image(result["result_image"])
        result_image.save(output_path)
        
        print(f"🎉 Style transfer completed!")
        print(f"💾 Result saved to: {output_path}")
        print(f"⚡ Processing time: {result['processing_time']:.2f} seconds")
        
        return result

# Example usage
if __name__ == "__main__":
    # Initialize client with your Azure Function URL
    client = StyleTransferClient("https://your-function-app.azurewebsites.net")
    
    # Process style transfer
    try:
        result = client.process_style_transfer(
            content_image_path="content.jpg",
            style_image_path="style.jpg",
            output_path="result.jpg",
            influence=0.8,
            creativity=0.7,
            additional_prompt="vibrant colors, artistic style"
        )
        
        print("✨ Style transfer successful!")
        
    except Exception as e:
        print(f"❌ Error: {e}")
