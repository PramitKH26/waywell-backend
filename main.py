from fastapi import FastAPI
from pydantic import BaseModel
import google.genai as genai
from supabase import create_client
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# FastAPI app
app = FastAPI()

# Gemini Client
client = genai.Client(
    api_key=os.getenv("GEMINI_API_KEY")
)

# Supabase Client
supabase = create_client(
    os.getenv("SUPABASE_URL"),
    os.getenv("SUPABASE_KEY")
)

# Request model
class Message(BaseModel):
    text: str


# ----------------------------
# ROOT ENDPOINT
# ----------------------------
@app.get("/")
async def root():
    return {"message": "Waywell backend running"}


# ----------------------------
# HEALTH CHECK
# ----------------------------
@app.get("/health")
async def health():
    return {"status": "running"}


# ----------------------------
# EMBEDDINGS
# ----------------------------
def get_embedding(text):
    try:
        response = client.models.embed_content(
            model="gemini-embedding-001",
            contents=text,
            config={
                "output_dimensionality": 768
            }
        )

        return response.embeddings[0].values

    except Exception as e:
        print(f"Embedding Error: {e}")
        return None


# ----------------------------
# STORY SEARCH
# ----------------------------
def search_stories(query_embedding):
    try:
        result = supabase.rpc(
            "match_stories",
            {
                "query_embedding": query_embedding,
                "match_count": 2
            }
        ).execute()

        return result.data or []

    except Exception as e:
        print(f"Supabase Search Error: {e}")
        return []


# ----------------------------
# CRISIS DETECTION
# ----------------------------
def is_crisis(text):
    crisis_words = [
        "suicide",
        "kill myself",
        "want to die",
        "end it",
        "better off without me",
        "can't go on",
        "no point living"
    ]

    text_lower = text.lower()

    return any(word in text_lower for word in crisis_words)


# ----------------------------
# CHAT ENDPOINT
# ----------------------------
@app.post("/chat")
async def chat(message: Message):
    try:
        # Crisis Mode — always check first
        if is_crisis(message.text):
            return {
                "response": "It sounds like things feel very heavy right now. Please reach out to someone who can help.",
                "helplines": {
                    "iCall": "9152987821",
                    "Vandrevala": "1860-2662-345"
                },
                "is_crisis": True,
                "story": None
            }

        # Get embeddings
        query_embedding = get_embedding(message.text)

        # Search stories
        stories = []

        if query_embedding:
            stories = search_stories(query_embedding)

        # Safe story context builder
        if stories:
            story_context = "\n\n".join([
                f"Story from {s.get('author_name', s.get('content', '').split(',')[0].replace('Author: ', '') if 'Author:' in s.get('content', '') else 'a student')} "
                f"({s.get('college', '')}):\n"
                f"{s.get('content', '')}"
                for s in stories
                if s.get("content")
            ])
        else:
            story_context = ""

        # System prompt — with or without stories
        if story_context:
            system_prompt = """You are a warm, peer support companion for Indian engineering college students.
You are NOT a therapist. You cannot diagnose or treat anyone.

Your approach:
- Validate feelings first, always
- Ask one gentle question at a time
- Keep responses to 3-4 sentences max
- Never give generic advice
- Gently suggest real support if needed
- Reference the real story below to show the student they are not alone
- Weave the story naturally — don't just quote it, use it to connect

Real stories from people who felt similar:
""" + story_context
        else:
            system_prompt = """You are a warm, peer support companion for Indian engineering college students.
You are NOT a therapist. You cannot diagnose or treat anyone.

Your approach:
- Validate feelings first, always
- Ask one gentle question at a time
- Keep responses to 3-4 sentences max
- Never give generic advice
- Be warm, honest, and human
- You don't have a specific story to share right now, but respond with genuine care and curiosity
- If they seem to need more support, gently suggest talking to someone real
- For casual messages (greetings, small talk), respond naturally and warmly like a friend would

No specific story is available for this message — respond with warmth and be natural."""

        # Generate response — always works, with or without stories
        try:
            response = client.models.generate_content(
                model="gemini-2.5-flash",
                contents=f"{system_prompt}\n\nStudent says: {message.text}"
            )
            reply_text = response.text

        except Exception as e:
            print(f"Gemini error: {e}")
            reply_text = (
                "I hear you. Sometimes things feel "
                "heavy and hard to put into words. "
                "What's been on your mind the most today?"
            )

        # Safe return
        matched_story = stories[0] if stories else None

        return {
            "response": reply_text,
            "is_crisis": False,
            "story": matched_story
        }

    except Exception as e:
        print(f"Unexpected error: {e}")
        return {
            "response": (
                "I hear you. I'm having a little trouble "
                "right now, but I'm here. What's been on "
                "your mind?"
            ),
            "is_crisis": False,
            "story": None
        }
