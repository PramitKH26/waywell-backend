import time
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
client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))

# Supabase Client
supabase = create_client(
    os.getenv("SUPABASE_URL"),
    os.getenv("SUPABASE_KEY")
)

# Request model
class Message(BaseModel):
    text: str
    history: list = []   # list of {role: 'user'|'assistant', content: '...'}


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
# HELPERS
# ----------------------------
def get_display_name(story):
    """Return a safe display name for a story author."""
    return (
        story.get("author_name")
        or story.get("name")
        or "a student"
    )


def get_embedding(text):
    try:
        response = client.models.embed_content(
            model="gemini-embedding-001",
            contents=text,
            config={"output_dimensionality": 768},
        )
        return response.embeddings[0].values
    except Exception as e:
        print(f"[EMBEDDING] Error: {e}")
        return None


def search_stories(query_embedding):
    try:
        result = supabase.rpc(
            "match_stories",
            {"query_embedding": query_embedding, "match_count": 2},
        ).execute()
        return result.data or []
    except Exception as e:
        print(f"[SEARCH] Error: {e}")
        return []


def is_crisis(text):
    crisis_words = [
        "suicide", "kill myself", "want to die", "end it",
        "better off without me", "can't go on", "no point living",
    ]
    text_lower = text.lower()
    return any(word in text_lower for word in crisis_words)


# ----------------------------
# CHAT ENDPOINT
# ----------------------------
@app.post("/chat")
async def chat(message: Message):
    t0 = time.time()
    history_len = len(getattr(message, "history", []))
    print(f"[CHAT] Request received, history: {history_len} msgs")

    try:
        # ── Crisis check (fast path, no LLM needed) ──────────────────────────
        if is_crisis(message.text):
            print(f"[CHAT] Crisis path, total: {time.time()-t0:.2f}s")
            return {
                "response": (
                    "It sounds like things feel very heavy right now. "
                    "Please reach out to someone who can help immediately."
                ),
                "helplines": {
                    "iCall":      "9152987821",
                    "Vandrevala": "1860-2662-345",
                    "KIRAN":      "1800-599-0019",
                },
                "is_crisis": True,
                "story": None,
            }

        # ── Embedding ─────────────────────────────────────────────────────────
        t1 = time.time()
        query_embedding = get_embedding(message.text)
        print(f"[CHAT] Embedding: {time.time()-t1:.2f}s")

        # ── Story search ──────────────────────────────────────────────────────
        t2 = time.time()
        stories = []
        if query_embedding:
            stories = search_stories(query_embedding)
        print(f"[CHAT] Supabase search: {time.time()-t2:.2f}s, "
              f"{len(stories)} stories found")

        # ── Story context ─────────────────────────────────────────────────────
        if stories:
            parts = []
            for s in stories:
                # Support both structured fields and legacy 'content' field
                if s.get("what_was_hard") or s.get("what_helped"):
                    parts.append(
                        f"Story from {get_display_name(s)}:\n"
                        f"What was hard: {s.get('what_was_hard', '')}\n"
                        f"What helped: {s.get('what_helped', '')}\n"
                        f"Where they are now: {s.get('where_now', '')}"
                    )
                elif s.get("content"):
                    parts.append(
                        f"Story from {get_display_name(s)} "
                        f"({s.get('college', '')}):\n"
                        f"{s.get('content', '')}"
                    )
            story_context = "\n\n".join(parts)
        else:
            story_context = ""

        # ── System prompt ─────────────────────────────────────────────────────
        memory_rule = (
            "\n\nMEMORY RULE: Use the conversation history to personalise "
            "your responses. If the user has shared personal details "
            "(anxiety, fear of judgment, specific struggles), remember them "
            "and adapt your tone. Never ask for information already shared."
        )

        if story_context:
            system_prompt = (
                "You are a warm peer support companion for Indian engineering "
                "college students. You are NOT a therapist.\n\n"
                "CRITICAL PRIVACY RULE: Only use the name or identifier given "
                "in the story context below. Never guess or reveal a real name "
                "beyond what is provided.\n\n"
                "Your approach:\n"
                "- Validate feelings first, always\n"
                "- Ask one gentle question at a time\n"
                "- Keep responses to 3-4 sentences maximum\n"
                "- Never give generic advice\n"
                "- Reference the real story below naturally to show they're not alone\n"
                "- If they need more support, gently suggest talking to someone real\n\n"
                "Real story from someone who felt similar:\n"
                + story_context
                + memory_rule
            )
        else:
            system_prompt = (
                "You are a warm peer support companion for Indian engineering "
                "college students. You are NOT a therapist.\n\n"
                "Your approach:\n"
                "- Validate feelings first, always\n"
                "- Ask one gentle question at a time\n"
                "- Keep responses to 3-4 sentences maximum\n"
                "- Never give generic advice\n"
                "- Be warm, honest, and genuinely caring\n"
                "- If they need more support, gently suggest talking to someone real\n"
                "- For casual messages or greetings, respond naturally like a friend\n\n"
                "No specific story available — respond with warmth and genuine curiosity."
                + memory_rule
            )

        # ── Build Gemini multi-turn contents ──────────────────────────────────
        contents = []
        for msg in message.history:
            role = "user" if msg.get("role") == "user" else "model"
            contents.append({
                "role":  role,
                "parts": [{"text": msg.get("content", "")}],
            })
        # Append current turn with system prompt prepended
        contents.append({
            "role":  "user",
            "parts": [{"text": f"{system_prompt}\n\nStudent says: {message.text}"}],
        })

        # ── Gemini call ───────────────────────────────────────────────────────
        t3 = time.time()
        try:
            response = client.models.generate_content(
                model="gemini-2.5-flash-lite",
                contents=contents,
                config={
                    "max_output_tokens": 200,   # ~3-4 sentences; keeps latency low
                    "temperature":       0.7,
                },
            )
            reply_text = response.text
            print(f"[CHAT] Gemini: {time.time()-t3:.2f}s, "
                  f"{len(reply_text)} chars")
        except Exception as e:
            print(f"[CHAT] Gemini ERROR after {time.time()-t3:.2f}s: {e}")
            reply_text = (
                "I hear you. Sometimes things feel heavy and hard to put "
                "into words. What's been on your mind the most today?"
            )

        matched_story = stories[0] if stories else None
        print(f"[CHAT] TOTAL: {time.time()-t0:.2f}s")

        return {
            "response":  reply_text,
            "is_crisis": False,
            "story":     matched_story,
        }

    except Exception as e:
        print(f"[CHAT] FATAL ERROR after {time.time()-t0:.2f}s: {e}")
        return {
            "response": (
                "I hear you. I'm having a little trouble right now, "
                "but I'm here. What's been on your mind?"
            ),
            "is_crisis": False,
            "story":     None,
        }
