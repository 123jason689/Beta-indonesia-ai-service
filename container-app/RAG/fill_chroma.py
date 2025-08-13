from langchain_core.documents import Document
from langchain_text_splitters import RecursiveCharacterTextSplitter
import chromadb

# Sample JSON data
data = [
    {
        "_id": "64c9b3e2a7f1d3a2b4c5d6e7",
        "title": "Candi Borobudur",
        "content": "Borobudur Temple is the world's largest Buddhist temple, located in Magelang, Central Java, Indonesia. It is a UNESCO World Heritage Site and one of the most popular tourist attractions in Southeast Asia. Built in the 8th to 9th centuries by the Syailendra Dynasty, the temple features magnificent mandala architecture and rich reliefs depicting the life of Buddha and the Jataka tales.",
        "author": "John Doe",
        "createdAt": "2025-08-02T10:00:00Z",
        "__v": 0
    },
    {
        "_id": "64c9b4a9a7f1d3a2b4c5d6e8",
        "title": "Monas",
        "content": "The National Monument, abbreviated as Monas or Tugu Monas, is a 132-meter-high memorial located in the center of Medan Merdeka Square in Central Jakarta. Monas was erected to commemorate the resistance and struggle of the Indonesian people to gain independence from the Dutch colonial government.",
        "author": "Jane Smith",
        "createdAt": "2025-08-01T15:30:00Z",
        "__v": 0
    }
]

# Create Document objects from JSON
raw_documents = [
    Document(
        page_content=item["content"],
        metadata={
            "title": item["title"],
            "author": item["author"],
            "createdAt": item["createdAt"],
            "source_id": item["_id"]
        }
    )
    for item in data
]

# Split the documents
text_splitter = RecursiveCharacterTextSplitter(
    chunk_size=300,
    chunk_overlap=100,
    length_function=len,
    is_separator_regex=False,
)

chunks = text_splitter.split_documents(raw_documents)

# Prepare to upload to ChromaDB
documents = []
metadata = []
ids = []

for i, chunk in enumerate(chunks):
    documents.append(chunk.page_content)
    ids.append(f"ID{i}")
    metadata.append(chunk.metadata)

# Initialize ChromaDB
CHROMA_PATH = "chroma_db"
chroma_client = chromadb.PersistentClient(path=CHROMA_PATH)
collection = chroma_client.get_or_create_collection(name="indonesian_culture")

# Add to ChromaDB
collection.upsert(
    documents=documents,
    metadatas=metadata,
    ids=ids
)
#update existing vectors if the ids already exist
#or insert new ones if the ids are new
#however, the for loop creates the same id
#where those ids will be overwritten/updated
#but other collections or documents not involved in this upsert will stay intact.
