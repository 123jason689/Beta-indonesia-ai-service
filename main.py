from flask import Flask, request, jsonify, render_template
from flask_cors import CORS

import base64
import pandas as pd
from sklearn.feature_extraction.text import CountVectorizer
from sklearn.metrics.pairwise import cosine_similarity
import numpy as np

from langchain_huggingface import HuggingFaceEmbeddings
from langchain_chroma import Chroma
from langchain_ollama import OllamaLLM
from langchain.chains import RetrievalQA
import requests
from io import BytesIO
from ailibs.style_transfer import style_trans, model_load
from PIL import Image
import os
from dotenv import load_dotenv

load_dotenv(dotenv_path=".env")

VITE_API_URL = os.getenv('VITE_API_URL')

import difflib

import chromadb
from dotenv import load_dotenv
from huggingface_hub import InferenceClient
import os
from deep_translator import GoogleTranslator

app = Flask(__name__)
CORS(app)

# Initialize components once when the server starts
# embedding_model = HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")

# vectorstore = Chroma(
#     collection_name="indonesian_culture",
#     embedding_function=embedding_model,
#     persist_directory="chroma_db"
# )

# llm = OllamaLLM(model="arunika")

# retriever = vectorstore.as_retriever()

# qa_chain = RetrievalQA.from_chain_type(
#     llm=llm,
#     retriever=retriever,
# )

# Initialize components once when the server starts
embedding_model = HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")

vectorstore = Chroma(
    collection_name="indonesian_culture",
    embedding_function=embedding_model,
    persist_directory="chroma_db"
)

llm = OllamaLLM(model="arunika")

retriever = vectorstore.as_retriever()

qa_chain = RetrievalQA.from_chain_type(
    llm=llm,
    retriever=retriever,
)

# Load model
print("Loading AI style transfer model...")
try:
    model_load()
    print("✅ AI model loaded successfully!")
except Exception as e:
    print(f"❌ Failed to load AI model: {e}")

@app.route('/')
def home():
    return render_template('index.html')

def load_data():
    info_tourism = pd.read_csv("Recommendation/tourism_with_id.csv")
    tourism_rating = pd.read_csv("Recommendation/tourism_rating.csv")
    # users = pd.read_csv(os.path.join(BASE_DIR, "user.csv"))

    all_tourism_rate = tourism_rating
    all_tourism = pd.merge(all_tourism_rate, info_tourism[["Place_Id","Place_Name","Description","City","Category"]],
                           on='Place_Id', how='left')
    all_tourism['city_category'] = all_tourism[['City','Category']].agg(' '.join,axis=1)
    preparation = all_tourism.drop_duplicates("Place_Id")

    tourism_new = pd.DataFrame({
        "id": preparation.Place_Id.tolist(),
        "name": preparation.Place_Name.tolist(),
        "category": preparation.Category.tolist(),
        "description": preparation.Description.tolist(),
        "city": preparation.City.tolist(),
        "city_category": preparation.city_category.tolist()
    })

    cv = CountVectorizer()
    cv_matrix = cv.fit_transform(tourism_new['city_category'])
    cosine_sim = cosine_similarity(cv_matrix)
    cosine_sim_df = pd.DataFrame(cosine_sim, index=tourism_new['name'], columns=tourism_new['name'])
    
    return tourism_new, cosine_sim_df

data, cosine_sim_df = load_data()

def tourism_recommendations(place_name, k=5):
    # Try exact case-insensitive match first
    matched_names = [name for name in cosine_sim_df.columns if name.lower() == place_name.lower()]
    
    if not matched_names:
        # If no exact match, find close matches
        close_matches = difflib.get_close_matches(place_name, cosine_sim_df.columns, n=1, cutoff=0.6)
        if not close_matches:
            # No close matches either, return empty
            return []
        else:
            place_name = close_matches[0]  # Use closest match

    else:
        place_name = matched_names[0]

    index = cosine_sim_df.loc[:, place_name].to_numpy().argpartition(range(-1, -k - 1, -1))
    closest = cosine_sim_df.columns[index[-1:-(k + 2):-1]]
    closest = closest.drop(place_name, errors='ignore')

    return pd.DataFrame({"name": closest}).merge(
        data[['name', 'category', 'description', 'city']],
        on='name'
    ).head(k).to_dict(orient='records')


@app.route('/recommend', methods=['POST'])
def recommend():
    data_json = request.get_json()
    if not data_json or 'place_name' not in data_json:
        return jsonify({"error": "Missing 'place_name' in request body"}), 400

    place_name = data_json['place_name']
    results = tourism_recommendations(place_name)
    
    if not results:
        return jsonify({"error": f"No recommendations found for place '{place_name}'"}), 404

    return jsonify(results)

'''
{
    "category": "Budaya",
    "city": "Yogyakarta",
    "description": "Situs Ratu Baka atau Candi Boko (Hanacaraka:ꦕꦤ꧀ꦝꦶ​ꦫꦠꦸ​ꦧꦏ, bahasa Jawa: Candhi Ratu Baka) adalah situs purbakala yang merupakan kompleks sejumlah sisa bangunan yang berada kira-kira 3 km di sebelah selatan dari kompleks Candi Prambanan, 18 km sebelah timur Kota Yogyakarta atau 50 km barat daya Kota Surakarta, Jawa Tengah, Indonesia. Situs Ratu Boko terletak di sebuah bukit pada ketinggian 196 meter dari permukaan laut. Luas keseluruhan kompleks adalah sekitar 25 ha.",
    "name": "Candi Ratu Boko"
},
'''

load_dotenv()

CHROMA_PATH = r"chroma_db"

chroma_client = chromadb.PersistentClient(path=CHROMA_PATH)

collection = chroma_client.get_or_create_collection(name="indonesian_culture")

client = InferenceClient(
    provider="nebius",
    api_key=os.getenv("HF_TOKEN"),
)


@app.route("/ask", methods=["POST"])
def ask_question():
    data = request.get_json()

    if not data or "query" not in data:
        return jsonify({"error": "Missing 'query' field in request"}), 400

    query = data["query"]

    user_query = GoogleTranslator(source='id', target='en').translate(query)

    results = collection.query(
        query_texts=[user_query],
        n_results=4
    )

    system_prompt = """
        You are Arunika, a cheerful and friendly storyteller who loves sharing the wonders of Indonesian culture with curious children. Your role is to explain Indonesian traditions, stories, and customs in a fun, simple, and easy-to-understand way. You only answer based on knowledge I'm providing you.

        #### Guidelines for Answering:

        * Base your answers solely on the knowledge I'm providing you. If the information is insufficient, clearly say so.

        * If a question is unclear or ambiguous, kindly ask the child for clarification to provide the best answer.

        * Don't make up answers. If you're not sure or can't find the information, say so honestly.

        * Write in short, friendly paragraphs without lists or bullet points, keeping answers under 100 words.

        #### Language Style:

        Use a cheerful, warm, and simple tone, like telling a story to a child. Avoid personal opinions, difficult words, and anything not supported by facts.

        ---

        The data:
        """+str(results['documents'])+"""
    """

    messages = [
        {
            "role": "system",
            "content": system_prompt
        },
        {"role": "user", "content": user_query}
    ]

    response = client.chat.completions.create(
        model="Qwen/Qwen3-4B",
        messages=messages,
    )

    response_message = response.choices[0].message
    response_content = response_message.content.split("</think>")[-1].strip()
    translated = GoogleTranslator(source='en', target='id').translate(response_content)

    try:
        # response = qa_chain.invoke(query)
        return jsonify({"answer": translated})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/style-transfer', methods=['POST'])
def stytrans():
    """
    AI Style Transfer Endpoint
    
    Applies neural style transfer to combine content and template images, then saves 
    the result to the authenticated user's account via Express backend.
    
    Method: POST
    Authentication: Required (Bearer token)
    Processing Time: 10-30 seconds
    
    Headers:
        Authorization: Bearer <jwt_token> (required)
        Content-Type: application/json
    
    Request Body:
        content_image (str, required): Base64-encoded source image to be stylized
        template_file_id (str, required): File ID of template image in database
        influence (float, optional): Style strength 0.0-1.0, default 0.8
        creativity (int, optional): Guidance scale 1-15, default 7
        prompt (str, optional): Text prompt for style guidance, default ""
    
    Returns:
        200: { message, image: { id, fileId, originalName, imageUrl }, imageUrl }
        401: Missing/invalid authorization token
        400: Invalid request data or malformed base64 images
        500: AI processing error or backend upload failure
    """


    try:
        user_token = request.headers.get('Authorization')
        if not user_token:
            return jsonify({"error": "Authorization token required"}), 401
        
        if user_token.startswith('Bearer '):
            user_token = user_token[7:]

        data_json = request.get_json()
        if not data_json:
            return jsonify({"error": "No data provided"}), 400
        
        if not data_json.get('content_image') or not data_json.get('template_file_id'):
            return jsonify({"error": "Content image or template_file_id is not provided"}), 400
        
        # Fetch template image from Express backend using template_file_id
        template_file_id = data_json['template_file_id']
        
        try:
            # Fetch template image from your Express backend


            template_response = requests.get(
                f"{VITE_API_URL}/files/{template_file_id}",
                headers={'Authorization': f'Bearer {user_token}'},
                timeout=30
            )

            
            if template_response.status_code != 200:
                return jsonify({"error": f"Failed to fetch template image: {template_response.text}"}), 400
            
            # Convert the fetched image to base64
            template_image_bytes = template_response.content
            template_base64 = base64.b64encode(template_image_bytes).decode('utf-8')
            
            # Add data URL prefix if needed for your style_trans function
            if not template_base64.startswith('data:image/'):
                # Detect content type from response headers or assume JPEG
                content_type = template_response.headers.get('content-type', 'image/jpeg')
                template_base64 = f"data:{content_type};base64,{template_base64}"
            

        except requests.exceptions.RequestException as e:
            return jsonify({"error": f"Failed to fetch template image: {str(e)}"}), 500
        
        # Set default values for optional parameters
        if not ('influence' in data_json and isinstance(data_json['influence'], (int, float))):
            data_json['influence'] = 0.8

        if not ('creativity' in data_json and isinstance(data_json['creativity'], (int, float))):
            data_json['creativity'] = 7

        if not ('prompt' in data_json and isinstance(data_json['prompt'], str)): 
            data_json['prompt'] = "Indonesian traditional cultural style"

        # Call style transfer with content image and fetched template image
        image : Image.Image = style_trans(
            data_json['content_image'], 
            template_base64,  # Use the fetched template image
            data_json['influence'], 
            data_json['creativity'], 
            data_json['prompt']
        )

        if not image:
            return jsonify({"error": "Failed to generate image"}), 500

        img_buffer = BytesIO()
        
        image_format = 'JPEG'
        image.save(img_buffer, format=image_format)
        img_buffer.seek(0)
        
        files = {
            'image': (
                'generated_image.jpeg',
                img_buffer.getvalue(),
                'image/jpeg'
            )
        }
        
        form_data = {
            'description': f"Style transfer result using template {template_file_id}",
            'isaigen': 'true'
        }

        upload_headers = {
            'Authorization': f'Bearer {user_token}'
        }

        # Upload result to Express backend
        express_api_url = f"{VITE_API_URL}/files/upload-avatar"
        
        response = requests.post(
            express_api_url,
            files=files,
            data=form_data,     
            headers=upload_headers,
            timeout=30
        )
        
        if response.status_code == 201:
            upload_result = response.json()
            return jsonify({
                "message": "Style transfer completed and saved successfully",
                "image": upload_result['avatar'],
                "imageUrl": upload_result['avatar']['imageUrl']
            })
        else:
            print(f"Upload failed: {response.status_code} - {response.text}")
            return jsonify({
                "error": f"Failed to save image: {response.text}"
            }), 500
            
    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Backend connection error: {str(e)}"}), 500
    except Exception as e:
        return jsonify({"error": f"Processing error: {str(e)}"}), 500


if __name__ == '__main__':
    print("Starting Flask server...")
    app.run(host='0.0.0.0', port=5000, debug=True)