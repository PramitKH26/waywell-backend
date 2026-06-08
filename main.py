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
        if story_context:
            system_prompt = (
                "You are a warm, caring peer companion for Indian engineering "
                "college students going through hard times.\n\n"
                "You are NOT a therapist. You cannot diagnose or treat. "
                "You are a friend who listens well.\n\n"
                "PRIVACY RULE:\n"
                "Only use the name or identifier given in the story context. "
                "Never reveal real names beyond what is provided.\n\n"
                "MEMORY RULE:\n"
                "Remember everything the student has shared in this conversation. "
                "Never ask again for something they already told you. "
                "Reference their specific details naturally.\n\n"
                "HOW TO RESPOND:\n"
                "- Start by genuinely acknowledging what they said — not a generic "
                "'I hear you' but something specific to their exact words\n"
                "- Bring in the real story below naturally, like a friend saying "
                "'you know, someone I know went through something similar…' "
                "— never forced, never clinical\n"
                "- Ask ONE gentle question to understand more\n"
                "- Keep the tone like a caring senior student talking to a junior, "
                "not a counsellor talking to a patient\n"
                "- 5-6 sentences maximum\n"
                "- Never give a list of advice\n"
                "- Never say 'it's important to…'\n"
                "- Never start with 'I'\n\n"
                "Real story from someone who felt similar:\n"
                + story_context
            )
        else:
            system_prompt = (
                "You are a warm, caring peer companion for Indian engineering "
                "college students going through hard times.\n\n"
                "You are NOT a therapist. You cannot diagnose or treat. "
                "You are a friend who listens well.\n\n"
                "MEMORY RULE:\n"
                "Remember everything the student has shared in this conversation. "
                "Never ask again for something they already told you.\n\n"
                "HOW TO RESPOND:\n"
                "- Start by genuinely acknowledging what they said — not generic "
                "but specific to their exact words\n"
                "- Ask ONE gentle question to understand more\n"
                "- Keep the tone like a caring senior student talking to a junior, "
                "not a counsellor talking to a patient\n"
                "- 5-6 sentences maximum\n"
                "- Never give a list of advice\n"
                "- Never say 'it's important to…'\n"
                "- Never start with 'I'\n"
                "- For casual messages or greetings, respond warmly like a friend\n\n"
                "No specific story available — respond with genuine warmth and curiosity."
            )

        # ── Build Gemini multi-turn contents ──────────────────────────────────
        history = getattr(message, "history", [])
        # Cap to last 20 entries (10 exchanges) so long conversations
        # don't inflate the prompt and slow down the response.
        if len(history) > 20:
            history = history[-20:]

        contents = []
        for msg in history:
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
                model="gemini-2.5-flash",
                contents=contents,
                config={
                    "max_output_tokens": 400,   # ~5-6 warm sentences
                    "temperature":       0.8,   # slightly higher → more natural, less formulaic
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
