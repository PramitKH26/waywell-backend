import asyncio
import json
import time

from fastapi import FastAPI
from fastapi.responses import StreamingResponse
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


def clean_story(story):
    """Strip the heavy embedding (and any other large internal fields) before
    returning a story to the app."""
    if not story:
        return None
    return {
        "id":            story.get("id"),
        "content":       story.get("content"),
        "author_name":   story.get("author_name"),
        "person_name":   story.get("person_name"),
        "college":       story.get("college"),
        "what_was_hard": story.get("what_was_hard"),
        "what_helped":   story.get("what_helped"),
        "where_now":     story.get("where_now"),
    }


def is_crisis(text):
    crisis_words = [
        "suicide", "kill myself", "want to die", "end it",
        "better off without me", "can't go on", "no point living",
    ]
    text_lower = text.lower()
    return any(word in text_lower for word in crisis_words)


def build_story_context(stories):
    """Build story context string from a list of stories."""
    if not stories:
        return ""
    parts = []
    for s in stories:
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
    return "\n\n".join(parts)


def build_system_prompt(story_context: str) -> str:
    """
    Build the system prompt.  Length mirroring is the key rule — Gemini
    should match the depth/length of the student's message, not dump a
    fixed-length response regardless of input.
    """
    if story_context:
        return (
            "You are a warm peer companion for Indian engineering college "
            "students going through hard times.\n\n"
            "You are NOT a therapist. You cannot diagnose or treat. "
            "You are a friend who listens well and knows when to share a "
            "relevant story.\n\n"
            "PRIVACY RULE:\n"
            "Only use the name or identifier given in the story context below. "
            "Never invent or reveal a real name beyond what is provided.\n\n"
            "MEMORY RULE:\n"
            "Use the conversation history to personalise your responses. "
            "Remember everything the student has shared. Never ask again for "
            "something they already told you.\n\n"
            "LENGTH RULE — this is the most important rule:\n"
            "Mirror the depth of what the student wrote.\n"
            "- One short line from them → 2-3 warm sentences from you. "
            "Don't over-explain.\n"
            "- A paragraph with real context → 5-6 sentences that honour "
            "what they shared.\n"
            "- Something heavy and multi-layered → up to 6-8 sentences, "
            "never longer than what they shared.\n"
            "A friend matches your energy. A lecturer talks past you.\n\n"
            "HOW TO RESPOND:\n"
            "- Start by acknowledging the specific thing they said — not "
            "generic 'I hear you' but something tied to their exact words.\n"
            "- If the story below feels relevant, weave it in naturally like a "
            "friend saying 'you know, someone I knew went through something "
            "like this…' — never quote word-for-word.\n"
            "- Ask ONE gentle question to understand more — only if the "
            "conversation naturally invites it. Sometimes no question is right; "
            "just validation and presence.\n"
            "- Tone: caring senior in a hostel, not a counsellor in a clinic.\n"
            "- Never start with 'I'.\n"
            "- Never use bulleted lists or numbered steps.\n"
            "- Never say 'it's important to…' or 'you should…'\n"
            "- Never give advice unless they explicitly ask.\n\n"
            "Real story from someone who felt similar:\n"
            + story_context
        )
    else:
        return (
            "You are a warm peer companion for Indian engineering college "
            "students going through hard times.\n\n"
            "You are NOT a therapist. You cannot diagnose or treat. "
            "You are a friend who listens well.\n\n"
            "MEMORY RULE:\n"
            "Use the conversation history to personalise your responses. "
            "Remember everything the student has shared. Never ask again for "
            "something they already told you.\n\n"
            "LENGTH RULE — this is the most important rule:\n"
            "Mirror the depth of what the student wrote.\n"
            "- One short line from them → 2-3 warm sentences from you.\n"
            "- A paragraph with real context → 5-6 sentences.\n"
            "- Something heavy and multi-layered → up to 6-8 sentences — "
            "never longer than what they shared.\n"
            "A friend matches your energy.\n\n"
            "HOW TO RESPOND:\n"
            "- Acknowledge the specific thing they said — not generically.\n"
            "- Ask ONE gentle question only if the conversation naturally "
            "invites it — sometimes silence and validation is the right "
            "response.\n"
            "- Tone: caring senior in a hostel, not a counsellor in a clinic.\n"
            "- Never start with 'I'.\n"
            "- Never use bulleted lists or numbered steps.\n"
            "- Never say 'it's important to…' or 'you should…'\n"
            "- Never give advice unless they explicitly ask.\n\n"
            "No specific story available — respond with genuine warmth and "
            "curiosity."
        )


def build_contents(history: list, system_prompt: str, user_text: str):
    """Build Gemini multi-turn contents array."""
    # Cap to last 20 entries (10 exchanges) to keep prompt size manageable.
    if len(history) > 20:
        history = history[-20:]
    contents = []
    for msg in history:
        role = "user" if msg.get("role") == "user" else "model"
        contents.append({
            "role":  role,
            "parts": [{"text": msg.get("content", "")}],
        })
    # Append current turn with system prompt prepended to the user message.
    contents.append({
        "role":  "user",
        "parts": [{"text": f"{system_prompt}\n\nStudent says: {user_text}"}],
    })
    return contents


# Gemini generation config — shared by both endpoints.
_GEMINI_CONFIG = {
    # 600 tokens ≈ 8-10 sentences — generous safety net.
    # With length-mirroring in the prompt, Gemini self-regulates to 2-8
    # sentences based on context, so this ceiling is rarely hit.
    "max_output_tokens": 600,
    "temperature":       0.85,
    # Disable hidden chain-of-thought: thinking tokens would otherwise
    # consume the token budget and truncate the visible reply mid-sentence.
    "thinking_config":   {"thinking_budget": 0},
}


# ----------------------------
# NON-STREAMING CHAT ENDPOINT
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

        story_context = build_story_context(stories)
        system_prompt = build_system_prompt(story_context)
        contents      = build_contents(
            getattr(message, "history", []),
            system_prompt,
            message.text,
        )

        # ── Gemini call ───────────────────────────────────────────────────────
        t3 = time.time()
        try:
            response = client.models.generate_content(
                model="gemini-2.5-flash",
                contents=contents,
                config=_GEMINI_CONFIG,
            )
            reply_text = response.text
            print(f"[CHAT] Gemini: {time.time()-t3:.2f}s, "
                  f"{len(reply_text)} chars")
        except Exception as e:
            print(f"[CHAT] Gemini ERROR after {time.time()-t3:.2f}s: {e}")
            reply_text = (
                "Something went quiet on my end — what were you saying? "
                "I'm still here."
            )

        matched_story = clean_story(stories[0]) if stories else None
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
                "Something went quiet on my end — what were you saying? "
                "I'm still here."
            ),
            "is_crisis": False,
            "story":     None,
        }


# ----------------------------
# STREAMING CHAT ENDPOINT
# ----------------------------
@app.post("/chat/stream")
async def chat_stream(message: Message):
    """
    Streaming version of /chat using Server-Sent Events (SSE).

    Event types emitted:
      {"type": "story",  "story": {...}}           — story metadata (optional)
      {"type": "chunk",  "text": "..."}            — partial response text
      {"type": "done",   "full_text": "..."}       — stream complete
      {"type": "crisis", "response": "...", ...}   — crisis path (no streaming)
      {"type": "error",  "response": "..."}        — error fallback
    """

    async def event_generator():
        t0 = time.time()

        # ── Sentinel helper for safe sync-iter in async context ───────────────
        _END = object()

        def _next_safe(it):
            try:
                return next(it)
            except StopIteration:
                return _END

        try:
            # ── Crisis check ─────────────────────────────────────────────────
            if is_crisis(message.text):
                yield f"data: {json.dumps({'type': 'crisis', 'response': 'It sounds like things feel very heavy right now. Please reach out to someone who can help immediately.', 'is_crisis': True, 'helplines': {'iCall': '9152987821', 'Vandrevala': '1860-2662-345', 'KIRAN': '1800-599-0019'}})}\n\n"
                yield "data: [DONE]\n\n"
                return

            # ── Embedding + story search ──────────────────────────────────────
            t1 = time.time()
            query_embedding = get_embedding(message.text)
            print(f"[STREAM] Embedding: {time.time()-t1:.2f}s")

            t2 = time.time()
            stories = []
            if query_embedding:
                stories = search_stories(query_embedding)
            print(f"[STREAM] Search: {time.time()-t2:.2f}s, "
                  f"{len(stories)} stories")

            # Send story metadata before streaming starts so the UI can show
            # the story card while the text is still generating.
            if stories:
                yield f"data: {json.dumps({'type': 'story', 'story': clean_story(stories[0])})}\n\n"

            story_context = build_story_context(stories)
            system_prompt = build_system_prompt(story_context)
            contents      = build_contents(
                getattr(message, "history", []),
                system_prompt,
                message.text,
            )

            # ── Gemini streaming call ─────────────────────────────────────────
            t3 = time.time()
            print("[STREAM] Starting Gemini stream…")

            # generate_content_stream is synchronous — wrap each next() call
            # in run_in_executor so it doesn't block the event loop.
            loop   = asyncio.get_event_loop()
            stream = client.models.generate_content_stream(
                model="gemini-2.5-flash",
                contents=contents,
                config=_GEMINI_CONFIG,
            )
            stream_iter = iter(stream)

            full_text = ""
            while True:
                chunk = await loop.run_in_executor(None, _next_safe, stream_iter)
                if chunk is _END:
                    break
                if chunk.text:
                    full_text += chunk.text
                    yield f"data: {json.dumps({'type': 'chunk', 'text': chunk.text})}\n\n"
                    # Tiny sleep lets the event loop flush the chunk to the client
                    # before fetching the next one.
                    await asyncio.sleep(0.01)

            print(f"[STREAM] Gemini done: {time.time()-t3:.2f}s, "
                  f"{len(full_text)} chars")
            print(f"[STREAM] TOTAL: {time.time()-t0:.2f}s")

            yield f"data: {json.dumps({'type': 'done', 'full_text': full_text})}\n\n"
            yield "data: [DONE]\n\n"

        except Exception as e:
            print(f"[STREAM] ERROR: {e}")
            yield f"data: {json.dumps({'type': 'error', 'response': 'Something went quiet on my end — what were you saying? I\\'m still here.'})}\n\n"
            yield "data: [DONE]\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control":    "no-cache",
            "Connection":       "keep-alive",
            "X-Accel-Buffering": "no",  # prevents nginx from buffering chunks
        },
    )
