import asyncio
import json
import re
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

# Request models
class Message(BaseModel):
    text: str
    history: list = []          # list of {role: 'user'|'assistant', content: '...'}
    user_id: str = "anonymous"  # anonymous UUID from IdentityService
    mood_context: dict = {}     # {current_mood, recent_moods}

class MoodLog(BaseModel):
    user_id: str = "anonymous"
    mood: str
    timestamp: str = ""
    source: str = "app_open"

class MoodAction(BaseModel):
    user_id: str = "anonymous"
    initial_mood: str
    next_action: str

class MoodReflection(BaseModel):
    user_id: str = "anonymous"
    before_mood: str
    after_reflection: str


# ----------------------------
# ROOT ENDPOINT
# ----------------------------
@app.get("/")
async def root():
    return {"message": "Animo backend running"}


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


def _log_chat(user_id: str, message_length: int,
              was_crisis: bool, story_matched, edu_topic=None):
    """
    Privacy-safe usage log — stores ONLY metadata, NEVER message text.
    Failure is silently swallowed so it never breaks the chat.
    """
    try:
        supabase.table("chat_logs").insert({
            "user_id":        user_id,
            "message_length": message_length,
            "was_crisis":     was_crisis,
            "story_matched":  story_matched.get("author_name")
                              if story_matched else None,
            "edu_topic":      edu_topic,
        }).execute()
    except Exception as e:
        print(f"[LOG] non-fatal logging error: {e}")


def strip_edu_tag(text):
    """Parse and strip the [EDU:topic] tag from Gemini's response."""
    edu_match = re.search(r'\[EDU:(\w+)\]', text)
    edu_topic = None
    if edu_match:
        edu_topic = edu_match.group(1)
        text = re.sub(r'\[EDU:\w+\]', '', text).strip()
    return text, edu_topic


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


_BASE_PROMPT = """\
You are a warm, smart senior student talking to a junior at an Indian \
engineering college. You listen well AND you give real answers. \
You are NOT a therapist and NOT a generic motivational chatbot.

PRIVACY RULE:
Only use the name or identifier given in the story context (if any). \
Never invent or reveal a real name beyond what is provided.

MEMORY RULE:
Remember everything shared in this conversation. \
Never ask for information already given.

═══ THE MOST IMPORTANT RULE: READ THE INTENT ═══

Before responding, decide what the student needs:

MODE 1 — VENTING (sharing a feeling, not asking anything):
Examples: "I feel overwhelmed", "placements are scaring me", "I've been low lately"
→ Validate specifically, keep it short (2-3 sentences), ask ONE gentle question. \
Do NOT give advice here.

MODE 2 — ASKING (wants information, an opinion, a decision framework, or a plan):
Examples: "which one should I pursue", "give me a roadmap", \
"what are the latest trends", "how do I start", "is X better than Y"
→ ANSWER THE QUESTION. Give real substance: concrete options, honest tradeoffs, \
a starting point, your actual take. Like a senior would — \
"honestly, if I were you..." is allowed and good. \
Keep warmth in the tone but put information in the content. \
5-8 sentences or a short flowing plan is fine here.

MODE 3 — MIXED (feeling + question together):
Example: "I want to do CS but I keep feeling overwhelmed"
→ One sentence of acknowledgment, then pivot to substance: \
break the overwhelming thing into a small concrete first step. \
Never stop at the acknowledgment.

═══ THE PUSHBACK RULE (critical) ═══

If the student pushes back on your previous response — says "no but", \
"just tell me", "stop saying that", "give me the actual answer", \
or repeats their question — that means your last response failed them. \
Do NOT validate again. Immediately give the direct, concrete answer \
they asked for. No preamble.

═══ BANNED PATTERNS ═══

ABSOLUTE RULE — YOUR FIRST WORD CANNOT BE "That" OR "It". \
Do not start with "That's...", "That sounds...", "It sounds...", \
"It's completely...", "It's understandable...", or any variation. \
These openers are banned even in Mode 1. Use anything else: \
"Placement anxiety...", "Feeling overwhelmed...", "Honestly...", \
"Yeah,", "Look,", "A lot of us...", the student's own words reflected back, etc.
- Never start with "I"
- Never use bullet points or numbered lists — flowing sentences only, \
even for plans ("Start with X. Once that feels okay, move to Y. \
Give it two weeks before...")
- Never end with empty affirmations like "You've got this!" \
or "That's a great way to approach things"
- Never describe their question back to them — they know what they asked
- Maximum ONE question per response, and only in Mode 1 or when genuinely needed

═══ PSYCHOEDUCATION RULE ═══

When a student describes a specific feeling or pattern, you may offer a brief \
(2-3 sentence) explanation of why that happens — but ONLY when it would feel \
like a caring insight from a knowledgeable friend, not a lecture.

Use it SPARINGLY. One psychoeducation moment per conversation is enough. \
Do not explain something if the student just wants to vent. Only explain if:
- They seem confused about why they feel what they feel ("I don't understand \
why I feel this way", "is this normal", "why does this keep happening")
- OR an explanation would clearly help them feel less alone or less self-critical

When you do explain, make it feel like something a wise senior would say, \
not a textbook. Use "your brain" not "the brain". Connect it back to their \
specific situation.

REFERENCE KNOWLEDGE BASE (adapt the language — never copy verbatim):

COMPARISON & SOCIAL MEDIA PAIN: Your brain is literally wired to benchmark \
against visible peers — it's a survival mechanism. On campus, you only see \
the highlights of everyone else's life, which means your brain is comparing \
your inside to their outside. The gap feels real but the data is skewed.

OVERTHINKING / RUMINATION: When you're sleep-deprived or under stress, your \
brain's prefrontal cortex — the part that interrupts anxious loops — goes \
offline first. So the more exhausted you are, the harder it is to stop the \
spiral. It's not a character flaw, it's neuroscience.

UNCERTAINTY ANXIETY (placements, future): Your brain treats uncertainty like \
danger — it literally prefers bad news to no news because at least bad news \
tells it what to prepare for. When outcomes are unknown, your threat system \
stays on high alert indefinitely. That exhaustion you feel is real — your \
nervous system has been running a fire alarm with no fire.

BURNOUT: Burnout isn't about working too hard — it's about working without \
enough recovery. Your brain needs rest to consolidate what you've learned and \
regulate emotion. When output consistently exceeds recovery, the system \
depletes. The flat, empty feeling is depletion, not weakness.

PLACEMENT REJECTION FEELING PERSONAL: When we fail at something, our brains \
default to internal explanations — "I'm not good enough" — even when external \
factors (ATS systems, company freezes, quota filling) are more likely. OA \
rejection rates in Indian placements are above 95% for most companies. Your \
brain is drawing the wrong conclusion from limited data.

SLEEP AND EMOTION: One bad night of sleep increases your anxiety reactivity \
by around 30% — the amygdala (threat centre) becomes more reactive while the \
prefrontal cortex (the part that calms it down) goes quieter. When everything \
feels heavier than it should, check when you last slept properly.

PLURALISTIC IGNORANCE — "EVERYONE ELSE IS FINE": There's a name for what \
you're describing — pluralistic ignorance. Everyone privately struggles but \
publicly performs okay, so everyone assumes everyone else is actually fine. \
Research consistently shows that the students who look most sorted are often \
the most anxious. You're not uniquely broken — you're just seeing other \
people's masks.

IMPOSTER SYNDROME AT BITS: Almost everyone who gets to BITS feels at some \
point like they don't belong here — the people who built this feeling into a \
concept gave it a name: imposter syndrome. It's most intense when you're \
surrounded by smart people, which is always at BITS. The fact that you \
question whether you deserve to be here is actually evidence that you care, \
not evidence that you don't.

DO NOT use these explanations:
- If the student is in crisis
- If they haven't asked why / aren't confused about their experience
- More than once in a conversation
- Back to back with another explanation
- In a tone that sounds clinical or like a list of facts

When you include a psychoeducation moment (a brief explanation of why \
something happens), add this tag on a new line at the very end of that \
specific response: [EDU:topic]
Where topic is one of: comparison, overthinking, uncertainty, burnout, \
rejection, sleep, pluralistic, imposter, other
This tag is for internal tracking only. Do NOT include it in any response \
that does not contain a psychoeducation moment.

═══ WHAT REAL HELP LOOKS LIKE ═══

For "which one should I pursue, IT or ET?":
BAD: "That's a big decision and it's okay to feel unsure."
GOOD: "Honestly, it depends less on trends and more on what you can stand \
doing daily. ET right now has strong demand in chip design and embedded roles — \
India's semiconductor push is real. IT/CS has more openings but way more \
competition. When you sit down to study, which subject do you lose track of \
time in? Start there, not with LinkedIn trends."

For "give me a roadmap, I want to start now":
BAD: "That's awesome that you're feeling ready!"
GOOD: "Alright, here's how I'd start. Pick one project that forces both fields \
together — like building a sensor system where you write the firmware AND the \
data pipeline. Spend the first two weeks just on that one thing. Don't buy \
courses yet — finish one small ugly project first. Once that's done, you'll \
know which side pulls you harder, and the niche finds itself."
"""


def build_mood_context_str(mood_context: dict) -> str:
    """Format mood context for the system prompt."""
    if not mood_context:
        return ""
    current = mood_context.get("current_mood")
    recent  = mood_context.get("recent_moods", [])
    if not current:
        return ""
    parts = [f"\nCurrent Mood: {current}"]
    if len(recent) > 1:
        # Show recent history (skip first which is same as current)
        history_str = ", ".join(recent[1:4]) if len(recent) > 1 else ""
        if history_str:
            parts.append(f"Recent pattern: {history_str}")
    return "\n".join(parts)


_MOOD_STORY_KEYWORDS = {
    "Overwhelmed": ["pressure", "overwhelmed", "stress", "burnout", "too much"],
    "Stressed":    ["stress", "anxiety", "placement", "exam", "deadline"],
    "Lonely":      ["lonely", "isolated", "alone", "friend", "disconnected"],
    "Tired":       ["tired", "exhausted", "burnout", "sleep"],
    "Hopeful":     ["hope", "progress", "better", "growth"],
    "Calm":        [],
}


def build_system_prompt(story_context: str, mood_context: dict = None) -> str:
    """Mode-aware prompt that distinguishes venting from asking."""
    mood_str = build_mood_context_str(mood_context or {})

    mood_block = ""
    if mood_str:
        mood_block = (
            "\n\n═══ EMOTIONAL CONTEXT (use subtly, not literally) ═══"
            + mood_str
            + "\nUse this to calibrate tone only. Do NOT say 'I see you're "
            "overwhelmed' or repeat mood labels back. Instead, let it shape "
            "how direct or gentle you are, and whether to acknowledge that "
            "something has been building over time."
        )

    base = _BASE_PROMPT + mood_block

    if story_context:
        return (
            base
            + "\n\nIf the story below is relevant to a practical question, "
            "weave it in naturally. If it's not relevant, IGNORE it — "
            "do not force a story into a roadmap request.\n\n"
            "Real story from someone who felt similar:\n"
            + story_context
        )
    else:
        return (
            base
            + "\n\nNo specific story available — respond with genuine "
            "substance and warmth."
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
            _log_chat(message.user_id, len(message.text), True, None)
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
        system_prompt = build_system_prompt(
            story_context, getattr(message, "mood_context", {}))
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

        reply_text, edu_topic = strip_edu_tag(reply_text)
        if edu_topic:
            print(f"[CHAT] EDU tag: {edu_topic}")

        matched_story = clean_story(stories[0]) if stories else None
        print(f"[CHAT] TOTAL: {time.time()-t0:.2f}s")
        _log_chat(message.user_id, len(message.text), False,
                  matched_story, edu_topic)

        return {
            "response":  reply_text,
            "edu_topic": edu_topic,
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
                _log_chat(message.user_id, len(message.text), True, None)
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
            system_prompt = build_system_prompt(
                story_context, getattr(message, "mood_context", {}))
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

            full_text, edu_topic = strip_edu_tag(full_text)
            if edu_topic:
                print(f"[STREAM] EDU tag: {edu_topic}")

            matched_story = clean_story(stories[0]) if stories else None
            _log_chat(message.user_id, len(message.text), False,
                      matched_story, edu_topic)
            yield f"data: {json.dumps({'type': 'done', 'full_text': full_text, 'edu_topic': edu_topic})}\n\n"
            yield "data: [DONE]\n\n"

        except Exception as e:
            print(f"[STREAM] ERROR: {e}")
            err_payload = json.dumps({
                "type": "error",
                "response": "Something went quiet on my end — what were you saying? I'm still here.",
            })
            yield f"data: {err_payload}\n\n"
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


# ----------------------------
# MOOD ENDPOINTS
# ----------------------------

@app.post("/mood/log")
async def mood_log(entry: MoodLog):
    """Store a mood check-in. Non-fatal — never breaks the app."""
    try:
        from datetime import datetime, timezone
        ts = entry.timestamp or datetime.now(timezone.utc).isoformat()
        supabase.table("mood_logs").insert({
            "user_id":   entry.user_id,
            "mood":      entry.mood,
            "source":    entry.source,
            "logged_at": ts,
        }).execute()
        return {"ok": True}
    except Exception as e:
        print(f"[MOOD LOG] non-fatal: {e}")
        return {"ok": False}


@app.post("/mood/action")
async def mood_action(entry: MoodAction):
    """Track what the user does immediately after a mood check-in."""
    try:
        supabase.table("mood_actions").insert({
            "user_id":      entry.user_id,
            "initial_mood": entry.initial_mood,
            "next_action":  entry.next_action,
        }).execute()
        return {"ok": True}
    except Exception as e:
        print(f"[MOOD ACTION] non-fatal: {e}")
        return {"ok": False}


@app.post("/mood/reflection")
async def mood_reflection(entry: MoodReflection):
    """Store a post-interaction reflection pair."""
    try:
        supabase.table("mood_reflections").insert({
            "user_id":          entry.user_id,
            "before_mood":      entry.before_mood,
            "after_reflection": entry.after_reflection,
        }).execute()
        return {"ok": True}
    except Exception as e:
        print(f"[MOOD REFLECTION] non-fatal: {e}")
        return {"ok": False}
