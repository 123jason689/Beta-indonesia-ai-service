import os
import json
import base64
import time
import logging
import sys
import pandas as pd
import chromadb
from datetime import datetime
from azure.storage.blob import BlobServiceClient
from azure.storage.queue import QueueClient

# Add current directory to path for imports
sys.path.insert(0, '/app')

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Azure Storage configuration
STORAGE_CONNECTION_STRING = os.environ.get('AZURE_STORAGE_CONNECTION_STRING')
BLOB_CONTAINER = "ai-service-results"

class MultiServiceProcessor:
    def __init__(self):
        self.blob_service_client = BlobServiceClient.from_connection_string(
            STORAGE_CONNECTION_STRING
        )
        self.style_transfer_loaded = False
        self.rag_system_loaded = False
        self.recommendation_data_loaded = False
        
        # Ensure blob container exists
        try:
            self.blob_service_client.create_container(BLOB_CONTAINER)
        except Exception:
            pass  # Container might already exist
    
    def load_style_transfer_model(self):
        """Load the style transfer AI model if not already loaded"""
        if not self.style_transfer_loaded:
            logger.info("Loading Style Transfer model (SD v1.5 + ControlNet + IP-Adapter)...")
            try:
                from ailibs.style_transfer import model_load
                model_load()
                self.style_transfer_loaded = True
                logger.info("✅ Style Transfer model loaded successfully!")
            except Exception as e:
                logger.error(f"❌ Failed to load Style Transfer model: {e}")
                raise
    
    def load_rag_system(self):
        """Load the RAG system if not already loaded"""
        if not self.rag_system_loaded:
            logger.info("Loading RAG system (ChromaDB + Ollama)...")
            try:
                # Initialize ChromaDB
                self.chroma_client = chromadb.PersistentClient(path="/app/chroma_db")
                self.rag_collection = self.chroma_client.get_collection("cultural_documents")
                
                # Initialize Ollama client (if available in container)
                try:
                    from ollama import Client
                    self.ollama_client = Client()
                except ImportError:
                    logger.warning("Ollama not available, using fallback responses")
                    self.ollama_client = None
                
                self.rag_system_loaded = True
                logger.info("✅ RAG system loaded successfully!")
            except Exception as e:
                logger.error(f"❌ Failed to load RAG system: {e}")
                raise
    
    def load_recommendation_data(self):
        """Load the recommendation system data if not already loaded"""
        if not self.recommendation_data_loaded:
            logger.info("Loading Recommendation system data...")
            try:
                # Load tourism data
                self.tourism_df = pd.read_csv("/app/Recommendation/tourism_with_id.csv")
                self.tourism_rating_df = pd.read_csv("/app/Recommendation/tourism_rating.csv")
                self.user_df = pd.read_csv("/app/Recommendation/user.csv")
                
                self.recommendation_data_loaded = True
                logger.info("✅ Recommendation system data loaded successfully!")
            except Exception as e:
                logger.error(f"❌ Failed to load Recommendation system data: {e}")
                raise
    
    def process_style_transfer(self, job_data):
        """Process style transfer job using AI models"""
        try:
            self.load_style_transfer_model()
            
            from ailibs.style_transfer import style_trans
            from PIL import Image
            from io import BytesIO
            
            logger.info(f"Processing style transfer job: {job_data['job_id']}")
            
            # Decode base64 images
            content_image_data = base64.b64decode(job_data['content_image'])
            style_image_data = base64.b64decode(job_data['style_image'])
            
            # Convert to PIL Images
            content_image = Image.open(BytesIO(content_image_data))
            style_image = Image.open(BytesIO(style_image_data))
            
            # Process the style transfer
            result_image = style_trans(
                content_image,
                style_image,
                strength=job_data.get('strength', 0.8)
            )
            
            # Convert result to base64 for storage
            img_buffer = BytesIO()
            result_image.save(img_buffer, format='JPEG', quality=85)
            img_buffer.seek(0)
            result_base64 = base64.b64encode(img_buffer.getvalue()).decode()
            
            # Upload result to blob storage
            result_data = {
                "job_id": job_data['job_id'],
                "service_type": "style_transfer",
                "status": "completed",
                "result_image": result_base64,
                "processing_time": time.time() - job_data.get('start_time', time.time()),
                "timestamp": datetime.utcnow().isoformat()
            }
            
            self.upload_result(job_data['job_id'], result_data)
            logger.info(f"Style transfer completed: {job_data['job_id']}")
            return result_data
            
        except Exception as e:
            logger.error(f"Error processing style transfer: {str(e)}")
            error_result = {
                "job_id": job_data['job_id'],
                "service_type": "style_transfer",
                "status": "error",
                "error": str(e),
                "timestamp": datetime.utcnow().isoformat()
            }
            self.upload_result(job_data['job_id'], error_result)
            raise
    
    def process_rag_chat(self, job_data):
        """Process RAG chat using ChromaDB and Ollama"""
        try:
            self.load_rag_system()
            
            logger.info(f"Processing RAG chat job: {job_data['job_id']}")
            question = job_data['question']
            
            # Query ChromaDB for relevant documents
            results = self.rag_collection.query(
                query_texts=[question],
                n_results=5
            )
            
            # Combine relevant documents
            context = "\n".join(results['documents'][0]) if results['documents'] else ""
            
            # Generate response using Ollama or fallback
            if self.ollama_client:
                try:
                    response = self.ollama_client.generate(
                        model='arunika',
                        prompt=f"Context: {context}\n\nQuestion: {question}\n\nAnswer:",
                        stream=False
                    )
                    answer = response['response']
                except Exception as e:
                    logger.warning(f"Ollama error: {e}, using fallback")
                    answer = self.generate_fallback_response(question, context)
            else:
                answer = self.generate_fallback_response(question, context)
            
            result_data = {
                "job_id": job_data['job_id'],
                "service_type": "rag_chat",
                "status": "completed",
                "question": question,
                "answer": answer,
                "context_used": len(context) > 0,
                "timestamp": datetime.utcnow().isoformat()
            }
            
            self.upload_result(job_data['job_id'], result_data)
            logger.info(f"RAG chat completed: {job_data['job_id']}")
            return result_data
            
        except Exception as e:
            logger.error(f"Error processing RAG chat: {str(e)}")
            error_result = {
                "job_id": job_data['job_id'],
                "service_type": "rag_chat",
                "status": "error",
                "error": str(e),
                "timestamp": datetime.utcnow().isoformat()
            }
            self.upload_result(job_data['job_id'], error_result)
            raise
    
    def process_recommendation(self, job_data):
        """Process tourism recommendation using pandas and collaborative filtering"""
        try:
            self.load_recommendation_data()
            
            logger.info(f"Processing recommendation job: {job_data['job_id']}")
            
            user_id = job_data['user_id']
            preferences = job_data['preferences']
            limit = job_data.get('limit', 10)
            
            # Filter tourism data based on preferences
            filtered_df = self.tourism_df.copy()
            
            if 'category' in preferences:
                filtered_df = filtered_df[filtered_df['Category'] == preferences['category']]
            
            if 'city' in preferences:
                filtered_df = filtered_df[filtered_df['City'] == preferences['city']]
            
            if 'max_price' in preferences:
                filtered_df = filtered_df[filtered_df['Price'] <= preferences['max_price']]
            
            if 'min_rating' in preferences:
                filtered_df = filtered_df[filtered_df['Rating'] >= preferences['min_rating']]
            
            # Sort by rating and get top recommendations
            recommendations = filtered_df.nlargest(limit, 'Rating')
            
            # Convert to list of dictionaries
            recommendation_list = []
            for _, row in recommendations.iterrows():
                recommendation_list.append({
                    "place_id": row['Place_Id'],
                    "place_name": row['Place_Name'],
                    "description": row['Description'],
                    "category": row['Category'],
                    "city": row['City'],
                    "price": row['Price'],
                    "rating": row['Rating'],
                    "time_minutes": row['Time_Minutes'],
                    "latitude": row['Lat'],
                    "longitude": row['Long']
                })
            
            result_data = {
                "job_id": job_data['job_id'],
                "service_type": "recommendation",
                "status": "completed",
                "user_id": user_id,
                "preferences_used": preferences,
                "recommendations": recommendation_list,
                "total_found": len(recommendation_list),
                "timestamp": datetime.utcnow().isoformat()
            }
            
            self.upload_result(job_data['job_id'], result_data)
            logger.info(f"Recommendation completed: {job_data['job_id']} - {len(recommendation_list)} places found")
            return result_data
            
        except Exception as e:
            logger.error(f"Error processing recommendation: {str(e)}")
            error_result = {
                "job_id": job_data['job_id'],
                "service_type": "recommendation",
                "status": "error",
                "error": str(e),
                "timestamp": datetime.utcnow().isoformat()
            }
            self.upload_result(job_data['job_id'], error_result)
            raise
    
    def generate_fallback_response(self, question, context):
        """Generate a simple fallback response when Ollama is not available"""
        if "borobudur" in question.lower():
            return "Borobudur adalah candi Buddha terbesar di dunia yang terletak di Magelang, Jawa Tengah. Candi ini dibangun pada abad ke-8 hingga ke-9 oleh Dinasti Syailendra."
        elif "monas" in question.lower():
            return "Monumen Nasional (Monas) adalah monumen setinggi 132 meter yang terletak di Jakarta Pusat. Monas didirikan untuk mengenang perjuangan kemerdekaan Indonesia."
        else:
            return "Maaf, saya memerlukan informasi lebih lanjut untuk menjawab pertanyaan Anda tentang budaya Indonesia. Bisa tolong berikan pertanyaan yang lebih spesifik?"
    
    def upload_result(self, job_id, result_data):
        """Upload result to blob storage"""
        blob_client = self.blob_service_client.get_blob_client(
            container=BLOB_CONTAINER,
            blob=f"results/{job_id}.json"
        )
        blob_client.upload_blob(json.dumps(result_data), overwrite=True)

def main():
    """Main processor loop for all AI services"""
    logger.info("Starting Multi-Service AI Processor...")
    logger.info("Services: Style Transfer, RAG Chat, Tourism Recommendation")
    
    # Check GPU availability for style transfer
    try:
        import torch
        if torch.cuda.is_available():
            logger.info(f"CUDA available: {torch.cuda.get_device_name(0)}")
            logger.info(f"CUDA memory: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.1f} GB")
        else:
            logger.warning("CUDA not available - Style Transfer will run on CPU")
    except ImportError:
        logger.warning("PyTorch not available for GPU check")
    
    # Get Azure Storage connection string
    connection_string = os.getenv('AZURE_STORAGE_CONNECTION_STRING')
    if not connection_string:
        logger.error("AZURE_STORAGE_CONNECTION_STRING environment variable not set")
        return
    
    # Initialize processor
    processor = MultiServiceProcessor()
    
    # Initialize queue clients for all services
    queues = {
        "style_transfer": QueueClient.from_connection_string(connection_string, queue_name="style-transfer-jobs"),
        "rag_chat": QueueClient.from_connection_string(connection_string, queue_name="rag-jobs"),
        "recommendation": QueueClient.from_connection_string(connection_string, queue_name="recommendation-jobs")
    }
    
    logger.info("Multi-service processor ready, waiting for jobs...")
    idle_count = 0
    max_idle_time = 120  # 2 minutes for cost optimization
    
    while True:
        try:
            message_found = False
            
            # Check all queues for jobs
            for service_name, queue_client in queues.items():
                messages = queue_client.receive_messages(
                    max_messages=1,
                    visibility_timeout=600  # 10 minutes to process
                )
                
                for message in messages:
                    message_found = True
                    idle_count = 0  # Reset idle counter
                    
                    try:
                        # Parse job data
                        job_data = json.loads(message.content)
                        job_data['start_time'] = time.time()
                        
                        logger.info(f"Received {service_name} job: {job_data.get('job_id', 'unknown')}")
                        
                        # Process based on service type
                        if service_name == "style_transfer":
                            processor.process_style_transfer(job_data)
                        elif service_name == "rag_chat":
                            processor.process_rag_chat(job_data)
                        elif service_name == "recommendation":
                            processor.process_recommendation(job_data)
                        
                        # Delete message from queue (job completed)
                        queue_client.delete_message(message)
                        logger.info(f"{service_name} job completed successfully")
                        
                    except Exception as e:
                        logger.error(f"Error processing {service_name} job: {str(e)}")
                        # Leave message in queue for retry
            
            if not message_found:
                idle_count += 1
                if idle_count >= max_idle_time:
                    logger.info("No jobs for 2 minutes, shutting down to save costs...")
                    break
                    
            time.sleep(1)  # Check every second when idle
                
        except Exception as e:
            logger.error(f"Error in main loop: {str(e)}")
            time.sleep(5)  # Wait before retrying

if __name__ == "__main__":
    main()
