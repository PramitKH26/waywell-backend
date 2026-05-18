from fastapi import FastAPI
from pydantic import BaseModel
import google.genai as genai
from supabase import create_client
import os
from dotenv import load_dotenv

load_dotenv()

app = FastAPI()

client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))
supabase = create_client(os.getenv("SUPABASE_URL"), os.getenv("SUPABASE_KEY"))

class Message(BaseModel):
    text: str

def get_embedding(text):
    try:
        response = client.models.embed_content(
            model="models/text-embedding-004",
            text=text
        )
        return response.embedding
    except Exception as e:
        print(f"Embedding error: {e}")
        return None

def search_stories(query_embedding):
    try:
        result = supabase.rpc("match_stories", {
            "query_embedding": query_embedding,
            "match_count": 2
        }).execute()
        return result.data or []
    except Exception:
        return []

def is_crisis(text):
    crisis_words = [
        "suicide", "kill myself", "end it", "want to die",
        "no point living", "better off without me", "can't go on"
    ]
    text_lower = text.lower()
    return any(word in text_lower for word in crisis_words)

@app.post("/chat")
async def chat(message: Message):
    
    if is_crisis(message.text):
        return {
            "response": "It sounds like things feel very heavy right now. Please reach out to someone who can help.",
            "helplines": {
                "iCall": "9152987821",
                "Vandrevala": "1860-2662-345"
            },
            "is_crisis": True
        }
    
    query_embedding = get_embedding(message.text)
    stories = []
    if query_embedding:
        stories = search_stories(query_embedding)

    story_context = ""
    if stories:
        story_context = "\n\n".join([s['content'] for s in stories])
    
    system_prompt = """You are a warm, peer support companion for Indian college students. 
    You are NOT a therapist. You cannot diagnose or treat anyone.
    
    Your approach:
    - Validate feelings first before anything else
    - Ask one gentle question at a time
    - Use the real stories provided to show the student they are not alone
    - Keep responses short — 3-4 sentences maximum
    - Never give generic advice
    - If someone seems to need more help, gently suggest talking to someone real
    
    Real stories from people who felt similar things:
    """ + story_context
    
    response = client.models.generate_content(
        model="models/gemini-2.5-flash",
        contents=f"{system_prompt}\n\nStudent says: {message.text}"
    )
    
    return {
        "response": response.text,
        "is_crisis": False
    }

@app.get("/health")
async def health():
    return {"status": "running"}