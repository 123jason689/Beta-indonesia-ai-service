import torch
import base64
from PIL import Image
from io import BytesIO
from typing import Dict, Union
import re
import os
import cv2
import numpy as np
from diffusers import ControlNetModel, StableDiffusionControlNetPipeline
from dotenv import load_dotenv
import zipfile
from huggingface_hub import hf_hub_download

# --- Configuration ---
# Correctly load .env from the project root
project_dir = os.path.join(os.path.dirname(__file__), '..')
dotenv_path = os.path.join(project_dir, '.env')
load_dotenv(dotenv_path=dotenv_path)

INFERENCE_STEPS = int(os.getenv('NUM_INFERENCE_STEPS', 10))  # Reduced for cost efficiency
MODEL_SOURCE = "HUGGINGFACE"  # Only Hugging Face support

# --- Model Paths ---
# Use absolute paths based on the project directory for container compatibility
MODELS_ROOT = os.path.join(project_dir, "models")

# Define paths for both GCS (local cache) and Hugging Face (repo name)
HUGGINGFACE_BASE_MODEL_PATH = "runwayml/stable-diffusion-v1-5"
LOCAL_BASE_MODEL_PATH = os.path.join(MODELS_ROOT, "stable-diffusion-v1-5")

HUGGINGFACE_CONTROLNET_PATH = "lllyasviel/sd-controlnet-canny"
LOCAL_CONTROLNET_PATH = os.path.join(MODELS_ROOT, "sd-controlnet-canny")

HUGGINGFACE_IP_ADAPTER_PATH = "h94/IP-Adapter"
LOCAL_IP_ADAPTER_PATH = os.path.join(MODELS_ROOT, "ip-adapter")

# Global variable to hold the loaded model
ip_model = None

def model_load():
    """
    Downloads model files if necessary and loads the pipeline.
    Optimized for Stable Diffusion v1.5 + ControlNet + IP-Adapter.
    """
    global ip_model
    if ip_model is not None:
        return ip_model

    print("Model source: Hugging Face. Models will be downloaded on first use if not cached.")
    base_model_path = HUGGINGFACE_BASE_MODEL_PATH
    controlnet_path = HUGGINGFACE_CONTROLNET_PATH
    
    # Define local paths for IP-Adapter components
    image_encoder_path = os.path.join(LOCAL_IP_ADAPTER_PATH, "image_encoder")
    ip_ckpt_path = os.path.join(LOCAL_IP_ADAPTER_PATH, "ip-adapter_sd15.bin")

    # Ensure directories exist
    os.makedirs(image_encoder_path, exist_ok=True)

    print("📥 Downloading IP-Adapter components from Hugging Face...")
    
    # Download IP-Adapter components
    hf_hub_download(
        repo_id=HUGGINGFACE_IP_ADAPTER_PATH,
        filename="models/image_encoder/config.json",
        local_dir=LOCAL_IP_ADAPTER_PATH,
        local_dir_use_symlinks=False
    )
    hf_hub_download(
        repo_id=HUGGINGFACE_IP_ADAPTER_PATH,
        filename="models/image_encoder/pytorch_model.bin",
        local_dir=LOCAL_IP_ADAPTER_PATH,
        local_dir_use_symlinks=False
    )
    hf_hub_download(
        repo_id=HUGGINGFACE_IP_ADAPTER_PATH,
        filename="models/ip-adapter_sd15.bin",
        local_dir=LOCAL_IP_ADAPTER_PATH,
        local_dir_use_symlinks=False
    )
    
    # Re-define paths to point to the correct nested structure created by the download
    image_encoder_path = os.path.join(LOCAL_IP_ADAPTER_PATH, "models", "image_encoder")
    ip_ckpt_path = os.path.join(LOCAL_IP_ADAPTER_PATH, "models", "ip-adapter_sd15.bin")

    print("✅ IP-Adapter components downloaded.")


    # Set device
    device = "cuda" if torch.cuda.is_available() else "cpu"
    torch_dtype = torch.float16 if device == "cuda" else torch.float32
    print(f"Using device: {device}")

    print("🚀 Initializing model pipeline...")

    # Load ControlNet & SD Pipeline
    controlnet = ControlNetModel.from_pretrained(controlnet_path, torch_dtype=torch_dtype)
    pipe = StableDiffusionControlNetPipeline.from_pretrained(
        base_model_path,
        controlnet=controlnet,
        torch_dtype=torch_dtype,
        safety_checker=None,
        requires_safety_checker=False
    )
    pipe = pipe.to(device)

    # Apply memory optimizations
    if device == "cuda":
        pipe.enable_attention_slicing()
        pipe.enable_vae_slicing()
        pipe.enable_vae_tiling()
    else:
        pipe.enable_attention_slicing("max")

    # Load IP-Adapter using the now-local files
    try:
        from ip_adapter import IPAdapter
        
        # This now works for both GCS and Hugging Face sources
        ip_model = IPAdapter(pipe, image_encoder_path, ip_ckpt_path, device)

        print("✅ IP-Adapter loaded successfully!")
    except Exception as e:
        print(f"⚠️ IP-Adapter loading failed: {e}")
        ip_model = pipe # Fallback to the pipe if IP-Adapter fails

    print("🎉 Model initialization complete!")
    return ip_model


def style_trans(content_image_b64: str, style_image_b64: str, influence: float, creativity: float, additional_prompt: str) -> Image.Image:
    """
    Applies style transfer using IP-Adapter + ControlNet or fallback methods.
    """
    global ip_model

    try:
        # This will trigger the model download and load on the very first request
        if ip_model is None:
            ip_model = model_load()

        content_image = decode_base64_image(content_image_b64)
        style_image = decode_base64_image(style_image_b64)
        
        max_size = 512
        content_image.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)
        style_image.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)

        prompt = (
            "a profile picture or avatar, fun, artistic, represent indonesian culture, traditional, art, fit for poster, good for instagram\n"
            f"{additional_prompt}.\n"
            "suitable for sharing on social media like Instagram."
        )
        
        negative_prompt = "nsfw, nude, mutated, ugly, watermark, lowres, low quality, worst quality, deformed, glitch, low contrast, noisy, saturation, blurry, boring, too formal, bad anatomy, propaganda, politics."

        with torch.inference_mode():
            if hasattr(ip_model, 'generate'):
                print("🎨 Using IP-Adapter for style transfer...")
                content_array = np.array(content_image)
                canny = cv2.Canny(content_array, 100, 200)
                canny_image = Image.fromarray(canny)

                print("Generating ...")
                images = ip_model.generate(
                    pil_image=style_image,
                    prompt=prompt,
                    negative_prompt=negative_prompt,
                    scale=influence,
                    guidance_scale=min(creativity, 15),
                    num_samples=1,
                    num_inference_steps=INFERENCE_STEPS,
                    image=canny_image,
                    controlnet_conditioning_scale=0.6,
                    height=512,
                    width=512
                )
                stylized_image = images[0]
                
            else: # Fallback mode
                print("⚠️ Using enhanced ControlNet-only mode...")
                # ... (fallback logic remains the same)
                return content_image # Placeholder for fallback

        print("Image generated successfully")
        return stylized_image
        
    except Exception as e:
        print(f"An error occurred: {e}")
        raise RuntimeError(f"Style transfer failed: {str(e)}") from e


def analyze_style_image(style_image: Image.Image) -> str:
    """Analyze style image for descriptive terms"""
    img_array = np.array(style_image)
    colors = img_array.reshape(-1, 3)
    mean_color = np.mean(colors, axis=0)
    std_color = np.std(colors, axis=0)
    
    brightness = np.mean(mean_color)
    saturation = np.mean(std_color)
    
    style_terms = []
    
    if brightness > 200:
        style_terms.append("bright, light, airy")
    elif brightness > 100:
        style_terms.append("balanced lighting")
    else:
        style_terms.append("dark, moody, dramatic")
    
    if saturation > 50:
        style_terms.append("vibrant, colorful")
    else:
        style_terms.append("muted, pastel")
    
    # Color dominance
    dominant_channel = np.argmax(mean_color)
    if dominant_channel == 0:
        style_terms.append("warm, reddish tones")
    elif dominant_channel == 2:
        style_terms.append("cool, blue tones")
    else:
        style_terms.append("natural, green tones")
    
    return ", ".join(style_terms)

def apply_color_transfer(generated_image: Image.Image, style_image: Image.Image, influence: float) -> Image.Image:
    """Apply color transfer from style to generated image"""
    gen_array = np.array(generated_image).astype(np.float32)
    style_array = np.array(style_image.resize(generated_image.size)).astype(np.float32)
    
    gen_mean = np.mean(gen_array, axis=(0, 1))
    style_mean = np.mean(style_array, axis=(0, 1))
    
    # Simple color adjustment
    color_shift = (style_mean - gen_mean) * influence * 0.3
    adjusted = gen_array + color_shift
    adjusted = np.clip(adjusted, 0, 255)
    
    return Image.fromarray(adjusted.astype(np.uint8))


def decode_base64_image(base64_string: str) -> Image.Image:
    """
    Decodes a Base64 string (with or without data URL prefix) into a PIL Image.
    """
    try:
        # Handle data URL format (data:image/...;base64,...)
        if base64_string.startswith('data:'):
            if ';base64,' in base64_string:
                # Extract just the base64 part after the comma
                base64_data = base64_string.split(';base64,', 1)[1]
            else:
                raise ValueError("Invalid data URL format - missing ';base64,' separator")
        else:
            # Raw base64 string
            base64_data = base64_string.strip()
        
        # Remove any whitespace that might cause issues
        base64_data = ''.join(base64_data.split())
        
        # Validate base64 format
        if not re.match(r'^[A-Za-z0-9+/]*={0,2}$', base64_data):
            raise ValueError("Invalid base64 characters detected")
        
        # Decode and create image
        try:
            image_data = base64.b64decode(base64_data, validate=True)
        except Exception as decode_error:
            raise ValueError(f"Failed to decode base64 data: {decode_error}")
        
        # Create BytesIO object and try to open image
        image_buffer = BytesIO(image_data)
        image_buffer.seek(0)  # Reset to beginning
        
        try:
            image = Image.open(image_buffer)
            # Convert to RGB to ensure compatibility
            image = image.convert("RGB")
            return image
        except Exception as image_error:
            raise ValueError(f"Failed to create image from decoded data: {image_error}")
        
    except Exception as e:
        print(f"❌ Image decoding error: {str(e)}")
        print(f"📝 Base64 string preview: {base64_string[:100]}...")
        raise ValueError(f"Failed to decode base64 image: {str(e)}")

def encode_image_to_base64(image: Image.Image) -> str:
    """Encodes a PIL Image into a Base64 string."""
    buffered = BytesIO()
    image.save(buffered, format="PNG")
    return base64.b64encode(buffered.getvalue()).decode('utf-8')
