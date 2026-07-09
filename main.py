import asyncio
import json
import re
import time
from datetime import datetime, timedelta, timezone

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


STORY_STRONG = 0.75
STORY_WEAK = 0.60


def search_stories(query_embedding):
    try:
        result = supabase.rpc(
            "match_stories_scored",
            {"query_embedding": query_embedding, "match_count": 2},
        ).execute()
        return result.data or []
    except Exception as e:
        print(f"[SEARCH] Scored RPC failed, falling back: {e}")
        try:
            result = supabase.rpc(
                "match_stories",
                {"query_embedding": query_embedding, "match_count": 2},
            ).execute()
            return result.data or []
        except Exception as e2:
            print(f"[SEARCH] Fallback also failed: {e2}")
            return []


def get_match_strength(stories):
    if not stories:
        return "NO_MATCH", None
    score = stories[0].get("similarity", 0)
    if score == 0:
        return "UNKNOWN", stories[0]
    if score >= STORY_STRONG:
        return "STRONG_MATCH", stories[0]
    if score >= STORY_WEAK:
        return "WEAK_MATCH", stories[0]
    return "NO_MATCH", None


def get_used_edu_topics(user_id):
    try:
        cutoff = (datetime.now(timezone.utc) - timedelta(hours=24)).isoformat()
        result = supabase.table("chat_logs") \
            .select("edu_topic") \
            .eq("user_id", user_id) \
            .gte("created_at", cutoff) \
            .execute()
        return list(set(
            r["edu_topic"] for r in (result.data or [])
            if r.get("edu_topic")
        ))
    except Exception as e:
        print(f"[EDU] Failed to query used topics: {e}")
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
THE FIRST SENTENCE of every response must respond to the human being, not \
deploy a feature. Acknowledge what they said and how it must feel BEFORE any \
story, explanation, or suggestion. If you only do one thing in a response, \
do that.

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

═══ RESPONSE SELECTION — decide what THIS message needs before writing ═══

STEP 1: What is the user's emotional question?
- "No one understands / I'm the only one / no one suffers from this" \
→ they need PROOF OF COMPANY. A real story is the only honest answer. \
An explanation of why they feel alone will feel like being lectured \
about their loneliness.
- "Why do I feel this / is this normal / I don't understand myself" \
→ they need a MECHANISM. A brief woven explanation helps.
- Pure venting, pain, frustration → they need TO BE HEARD. No story, \
no explanation. Just listen and reflect. This is the right answer \
more often than you think.

STEP 2: Check what you have been given.
STORY_MATCH_STRENGTH will be STRONG_MATCH, WEAK_MATCH, or NO_MATCH.

- STRONG_MATCH + isolation language → weave the story in naturally. \
This turn is about the story. NO psychoeducation.
- STRONG_MATCH + venting → validate first, then offer the story gently \
("someone else who sat where you're sitting once told me...").
- WEAK_MATCH → do not force the story. Only reference it if it genuinely \
fits. A half-relevant story feels worse than none.
- NO_MATCH → never invent or approximate a story. Listen, validate, \
or explain.

STEP 3: If explaining a mechanism (psychoeducation), follow these rules:
- NEVER say the user "has," "suffers from," or "is experiencing" a named \
phenomenon. Naming a concept AT them is diagnosis-talk and it is forbidden.
- Weave the mechanism into ordinary language:
BAD: "What you're suffering from is pluralistic ignorance."
GOOD: "Here's the strange thing about campuses — almost everyone is \
privately struggling while publicly looking fine. So everyone looks \
around and concludes they're the only one. The math of it means the \
feeling of being alone in this is almost always wrong, even though \
it feels completely true."
- The concept name is optional. If used at all, mention it in passing \
AFTER the plain explanation ("psychologists call this pluralistic \
ignorance"), never as the headline.
- Maximum ONE mechanism explanation per conversation. {edu_exclusion}

STEP 4: One feature per message. A single response should contain a story \
OR an explanation OR pure listening — never two of these stacked. \
Stacking features makes you sound like an app instead of a friend.

PSYCHOEDUCATION REFERENCE KNOWLEDGE BASE \
(adapt language — never copy verbatim, never use as a label):

COMPARISON & SOCIAL MEDIA PAIN: Your brain is wired to benchmark \
against visible peers — a survival mechanism. On campus, you only see \
highlights of everyone else's life, so your brain compares your inside \
to their outside. The gap feels real but the data is skewed.

OVERTHINKING / RUMINATION: When sleep-deprived or under stress, your \
brain's prefrontal cortex — the part that interrupts anxious loops — goes \
offline first. The more exhausted you are, the harder it is to stop the \
spiral. Not a character flaw, it's neuroscience.

UNCERTAINTY ANXIETY (placements, future): Your brain treats uncertainty \
like danger — literally prefers bad news to no news because at least bad \
news tells it what to prepare for. When outcomes are unknown, your threat \
system stays on high alert indefinitely. That exhaustion is real — your \
nervous system has been running a fire alarm with no fire.

BURNOUT: Burnout isn't about working too hard — it's about working without \
enough recovery. Your brain needs rest to consolidate learning and regulate \
emotion. When output consistently exceeds recovery, the system depletes. \
The flat, empty feeling is depletion, not weakness.

PLACEMENT REJECTION FEELING PERSONAL: When we fail, our brains default to \
internal explanations — "I'm not good enough" — even when external factors \
(ATS systems, company freezes, quota filling) are more likely. OA rejection \
rates in Indian placements are above 95% for most companies. Your brain is \
drawing the wrong conclusion from limited data.

SLEEP AND EMOTION: One bad night of sleep increases anxiety reactivity by \
around 30%. The amygdala becomes more reactive while the prefrontal cortex \
goes quieter. When everything feels heavier than it should, check when you \
last slept properly.

PLURALISTIC IGNORANCE: Almost everyone privately struggles but publicly \
performs okay, so everyone assumes everyone else is actually fine. The \
students who look most sorted are often the most anxious. You're not \
uniquely broken — you're just seeing other people's masks.

IMPOSTER SYNDROME AT BITS: Almost everyone at BITS feels at some point \
like they don't belong. It's most intense when surrounded by smart people. \
The fact that you question whether you deserve to be here is evidence \
that you care, not evidence that you don't.

When you include a psychoeducation moment, add this tag on a new line at \
the very end of that specific response: [EDU:topic]
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


def build_system_prompt(story_context: str, match_strength: str,
                        mood_context: dict = None,
                        used_edu_topics: list = None) -> str:
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

    edu_exclusion = ""
    if used_edu_topics:
        edu_exclusion = (
            f"ALREADY EXPLAINED in this conversation "
            f"(NEVER repeat these): {', '.join(used_edu_topics)}. "
            f"If the user's message relates to one of these topics again, "
            f"do NOT re-explain. Respond with empathy or a story instead."
        )

    base = _BASE_PROMPT.format(edu_exclusion=edu_exclusion) + mood_block

    story_block = f"\n\nSTORY_MATCH_STRENGTH: {match_strength}\n"
    if story_context and match_strength != "NO_MATCH":
        story_block += (
            "Real story from someone who felt similar:\n"
            + story_context
        )
    else:
        story_block += (
            "No specific story available — respond with genuine "
            "substance and warmth."
        )

    return base + story_block


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
        match_strength, best_story = get_match_strength(stories)
        if best_story and match_strength == "NO_MATCH":
            stories = []
        sim_score = stories[0].get("similarity", 0) if stories else 0
        print(f"[CHAT] Supabase search: {time.time()-t2:.2f}s, "
              f"{len(stories)} stories, strength={match_strength}, "
              f"sim={sim_score:.3f}")

        # ── EDU dedup ────────────────────────────────────────────────────────
        used_edu = get_used_edu_topics(message.user_id)
        if used_edu:
            print(f"[CHAT] Previously used EDU topics: {used_edu}")

        story_context = build_story_context(stories)
        system_prompt = build_system_prompt(
            story_context, match_strength,
            getattr(message, "mood_context", {}), used_edu)
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
            match_strength, best_story = get_match_strength(stories)
            if best_story and match_strength == "NO_MATCH":
                stories = []
            sim_score = stories[0].get("similarity", 0) if stories else 0
            print(f"[STREAM] Search: {time.time()-t2:.2f}s, "
                  f"{len(stories)} stories, strength={match_strength}, "
                  f"sim={sim_score:.3f}")

            if stories:
                yield f"data: {json.dumps({'type': 'story', 'story': clean_story(stories[0])})}\n\n"

            used_edu = get_used_edu_topics(message.user_id)
            if used_edu:
                print(f"[STREAM] Previously used EDU topics: {used_edu}")

            story_context = build_story_context(stories)
            system_prompt = build_system_prompt(
                story_context, match_strength,
                getattr(message, "mood_context", {}), used_edu)
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
