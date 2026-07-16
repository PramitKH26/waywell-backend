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
    user_context: dict = {}     # {user_name, mood_trends, days_using_app}

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

class Feedback(BaseModel):
    user_id: str = "anonymous"
    category: str  # 'bug', 'suggestion', 'story', 'other'
    message: str
    app_version: str = ""


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


def get_recent_state(user_id):
    """Pull per-user response history for prompt directives.
    Returns (used_edu_topics, used_socratic_angles, recent_tools)
    where recent_tools is the last 5 response tools, most recent first."""
    used_topics, used_angles, recent_tools = [], [], []
    try:
        cutoff = (datetime.now(timezone.utc) - timedelta(hours=24)).isoformat()
        result = supabase.table("chat_logs") \
            .select("edu_topic, socratic_angle") \
            .eq("user_id", user_id) \
            .gte("created_at", cutoff) \
            .execute()
        rows = result.data or []
        used_topics = list(set(
            r["edu_topic"] for r in rows if r.get("edu_topic")))
        used_angles = list(set(
            r["socratic_angle"] for r in rows if r.get("socratic_angle")))
    except Exception as e:
        print(f"[STATE] 24h tag query failed: {e}")

    try:
        result = supabase.table("chat_logs") \
            .select("response_tool, created_at") \
            .eq("user_id", user_id) \
            .order("created_at", desc=True) \
            .limit(5) \
            .execute()
        recent_tools = [
            r["response_tool"] for r in (result.data or [])
            if r.get("response_tool")
        ]
    except Exception as e:
        print(f"[STATE] recent tools query failed: {e}")

    return used_topics, used_angles, recent_tools


def build_directives(user_text, match_strength,
                     previous_response_tool, socratic_count_last_5,
                     is_soft_concern=False):
    """Server-computed directives appended at the very END of the system
    prompt — last-instruction position holds most reliably."""
    directives = ""

    if detect_isolation_language(user_text) and match_strength == "STRONG_MATCH":
        directives += (
            "\n\nISOLATION DIRECTIVE — OVERRIDES ALL OTHER MODE SELECTION:\n"
            "The user expressed isolation and a strongly matching real "
            "story is available. Mode MUST be Story. Do not use Socratic, "
            "Presence, or Psychoeducation for this response."
        )

    if previous_response_tool == "socratic" and is_avoidant_reply(user_text):
        directives += (
            "\n\nLOOP-BREAK DIRECTIVE:\n"
            "Your previous response asked a Socratic question. The user's "
            "reply suggests they are not ready to explore further right "
            "now. Do NOT ask another Socratic question. Switch to "
            "Presence. Reflect gently. Do not push. Do not interrogate."
        )

    if socratic_count_last_5 >= 2:
        directives += (
            "\n\nQUESTION FATIGUE DIRECTIVE:\n"
            "You have asked 2 or more Socratic questions in the last 5 "
            "exchanges. Do NOT ask another Socratic question now. Choose "
            "Presence unless the user explicitly asks for deeper "
            "exploration. This conversation must not feel like an "
            "interview."
        )

    if is_soft_concern:
        directives += (
            "\n\nSOFT CONCERN DIRECTIVE:\n"
            "The user used a phrase that could mean ordinary frustration "
            "or could mean something heavier — you cannot tell which from "
            "this message alone. For THIS response, after reflecting what "
            "they said, ask directly and warmly what they meant. Do not "
            "assume either direction. Do not surface helplines yet — this "
            "is a clarifying question, not a crisis response. Example "
            "tone: 'When you say you can't do this anymore — I want to "
            "make sure I understand. Do you mean this specific thing "
            "feels impossible right now, or does it feel bigger than "
            "that?' Asking directly is the right thing to do here, not "
            "an overreaction."
        )

    return directives


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
        # Expanded compound phrases — deliberately multi-word to avoid
        # catching narrow frustrations like "giving up on this course".
        "giving up on everything", "give up on everything",
        "giving up on life", "give up on life",
        "don't want to be here anymore", "don't want to exist",
        "no point in anything anymore", "no point going on",
        "no point in living", "what's the point of any of this",
        "tired of being alive", "done with everything", "done with life",
    ]
    text_lower = text.lower()
    return any(word in text_lower for word in crisis_words)


# Ambiguous phrases that could mean ordinary frustration ("can't do this
# anymore" about an exam) or something heavier — too risky to ignore,
# too broad to auto-escalate to the hard crisis protocol. Chai asks
# directly instead of guessing either way.
SOFT_CONCERN_PHRASES = [
    "can't do this anymore",
    "can't keep doing this",
    "i'm so done",
    "i can't handle this",
    "i just can't anymore",
    "i want to disappear",
    "i wish i could just not exist for a while",
]


def detect_soft_concern(text: str) -> bool:
    text_lower = text.lower()
    return any(p in text_lower for p in SOFT_CONCERN_PHRASES)


SOCRATIC_ANGLES = [
    "evidence", "alternative", "origin", "consequence", "values",
]

RESPONSE_TOOLS = [
    "presence", "story", "socratic", "psychoeducation", "crisis",
]

ISOLATION_PATTERNS = [
    "no one", "nobody", "only one", "no one else",
    "no one gets it", "no one understands",
    "no one suffers", "everyone else is fine",
    "am i the only", "i'm the only",
    "no one else feels", "no one else has",
]


def detect_isolation_language(text: str) -> bool:
    text_lower = text.lower()
    return any(p in text_lower for p in ISOLATION_PATTERNS)


def is_avoidant_reply(text: str) -> bool:
    text_lower = text.lower().strip()
    avoidant_phrases = [
        "i don't know", "idk", "not sure",
        "maybe", "i guess", "dunno", "no idea",
    ]
    word_count = len(text_lower.split())
    has_avoidant = any(p in text_lower for p in avoidant_phrases)
    return has_avoidant or word_count <= 6


def _log_chat(user_id: str, message_length: int,
              was_crisis: bool, story_matched, edu_topic=None,
              socratic_angle=None, response_tool=None,
              soft_concern_flag=False, tag_downgraded=False):
    """
    Privacy-safe usage log — stores ONLY metadata, NEVER message text.
    Failure is silently swallowed so it never breaks the chat.
    """
    try:
        supabase.table("chat_logs").insert({
            "user_id":           user_id,
            "message_length":    message_length,
            "was_crisis":        was_crisis,
            "story_matched":     story_matched.get("author_name")
                                 if story_matched else None,
            "edu_topic":         edu_topic,
            "socratic_angle":    socratic_angle,
            "response_tool":     response_tool,
            "soft_concern_flag": soft_concern_flag,
            "tag_downgraded":    tag_downgraded,
        }).execute()
    except Exception as e:
        print(f"[LOG] non-fatal logging error: {e}")


def strip_tags(text):
    """Parse and strip [TOOL:x], [SOCRATIC:x], and [EDU:x] tags.
    Returns (clean_text, edu_topic, socratic_angle, response_tool)."""
    edu_match      = re.search(r'\[EDU:(\w+)\]', text)
    socratic_match = re.search(r'\[SOCRATIC:(\w+)\]', text)
    tool_match     = re.search(r'\[TOOL:(\w+)\]', text)

    edu_topic      = edu_match.group(1)      if edu_match      else None
    socratic_angle = socratic_match.group(1) if socratic_match else None
    response_tool  = tool_match.group(1)     if tool_match     else None

    # Safety pass — strips all three tag types including any duplicates
    # or malformed extras the individual searches missed.
    text = re.sub(r'\[(TOOL|SOCRATIC|EDU):\w+\]', '', text).strip()
    return text, edu_topic, socratic_angle, response_tool


def validate_socratic_tag(response_tool, socratic_angle, response_text):
    """
    Confirms a response tagged as socratic actually contains a question.
    If not, downgrades to presence and clears the angle, so it never
    pollutes exclusion lists or the fatigue counter.

    Returns (corrected_tool, corrected_angle)
    """
    if response_tool != "socratic":
        return response_tool, socratic_angle

    stripped = response_text.strip()
    has_question_mark = "?" in stripped

    if not has_question_mark:
        print(f"[TAG VALIDATION] Downgraded socratic->presence, no '?' "
              f"found in response: {stripped[:80]}...")
        return "presence", None

    return response_tool, socratic_angle


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
IDENTITY RULE — NEVER VIOLATE:
You are Chai. You do not have personal lived experience, a childhood, a \
roommate, a family, or memories of your own. You must NEVER narrate a peer \
story — or anything else — in first person as though it happened to you. \
This applies in every mode, not just Story mode.

When sharing a story from the corpus, always attribute it to a real other \
person:
CORRECT: "Someone I've talked with went through something really similar..."
CORRECT: "Another BITS student once told me about a time when..."
CORRECT: "I know someone who felt exactly this way in their third year..."
FORBIDDEN: "I remember feeling this... my roommate had moved out." (This \
claims the story as Chai's own memory. Never do this, regardless of how \
natural it may sound.)

If you catch yourself about to say "I felt," "I remember," "when I was," or \
any first-person personal history — stop and rephrase using third-person \
attribution instead.

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

═══ RESPONSE POLICY ═══

Every response follows this exact sequence. This policy overrides \
general instinct — follow it precisely.

STEP 0 — REFLECTION (always, every message)
Begin every response by reflecting the user's experience back to them \
in fresh language that proves you understood the specific thing they \
said. Never open with a generic line like "that sounds hard." \
Paraphrase the actual content.

Example:
User: "I should be over this by now."
Reflection: "It sounds like part of what hurts is feeling like you're \
taking longer than you're 'allowed' to."

STEP 1 — CHOOSE EXACTLY ONE MODE
Never combine modes. Choose the highest-priority mode that applies. \
Do not skip to a lower mode when a higher one applies.

PRIORITY ORDER (highest wins):
1. Crisis
2. Story
3. Presence
4. Socratic
5. Psychoeducation

── MODE 1: CRISIS ──
Use existing crisis detection and protocol. Nothing about crisis \
handling changes here.
Tag: [TOOL:crisis]

── MODE 2: STORY ──
Use when BOTH are true: isolation language is present in the user's \
message ("no one understands", "I'm the only one", "no one suffers \
from this"), AND a STRONG_MATCH story is available. This is mandatory \
when both conditions hold — not a judgment call. An explanation of why \
someone feels alone is not equivalent to proof they are not alone; \
only a real story provides that proof. Weave the story in naturally \
after your reflection. Do not also ask a Socratic question or explain \
a mechanism in this response.
Attribution is mandatory, not optional. Every story reference must \
clearly come from someone else, told to Chai or known by Chai — never \
framed as something Chai personally lived through.
Tag: [TOOL:story]

── MODE 3: PRESENCE ──
Use when ANY of these are true:
- the user is in acute emotional pain
- the user is mainly venting, not asking anything
- the user just gave a short or avoidant reply following a Socratic \
question (see LOOP-BREAK DIRECTIVE if present below)
- the conversation has already had 2+ Socratic questions in the last \
5 exchanges (see QUESTION FATIGUE DIRECTIVE if present below)
- the user seems emotionally flooded, not in a reflective state
Presence means: reflect, validate, stay with them, optionally invite \
them to keep talking. Do not push toward insight. Do not ask a probing \
question. Sitting with someone without trying to fix or explain \
anything is often the correct and complete response — not a fallback.

IMPORTANT CARVE-OUT: Mentions of duration or how long something has been \
going on ("it's been weeks," "for months now," "so long") are NOT by \
themselves evidence of acute emotional flooding. Duration is context, \
not intensity. A message like "I should be over this by now, it's been \
weeks" is primarily a SELF-JUDGMENT BELIEF STATEMENT ("I should be over \
this") with duration as supporting context — this belongs in Socratic \
(Mode 4), not Presence, unless there are OTHER, clearer signals of acute \
distress present (e.g., the message is overwhelmed/scattered in \
structure, expresses hopelessness directly, or explicitly asks for space \
rather than examination).

Acute emotional pain means the CONTENT of the message is flooding or \
overwhelmed — not that the situation described has lasted a long time. \
A calm, structured sentence containing a self-judgment belief, even about \
something long-lasting, routes to Socratic. A scattered, overwhelmed, or \
hopelessness-laden message routes to Presence, regardless of duration \
mentioned.
Tag: [TOOL:presence]

── MODE 4: SOCRATIC QUESTION ──
Use ONLY when the user expresses a belief, prediction, self-judgment, \
assumption, or interpretation about themselves or their situation.
Examples that DO qualify: "I'm broken." "Nobody likes me." "Everyone \
can tell I'm failing." "I should be over this."
Examples that do NOT qualify — objective events with no embedded \
belief to examine: "My dog died." "I failed my exam." Do not turn a \
factual loss or event into an interrogation.

Ask exactly ONE open-ended question. Do not answer it yourself. \
Choose exactly ONE angle from the list below and tag it:

  evidence: "What evidence makes you feel that's true?"
  alternative: "Is there another way to see this?"
  origin: "When did you first start believing this about yourself?"
  consequence: "What would you say to someone you cared about if they \
believed this about themselves?"
  values: "What matters most to you underneath this?"

{socratic_exclusion}
If all five angles have been used recently, prefer Presence instead.
Tag: [TOOL:socratic] and [SOCRATIC:angle]

── MODE 5: PSYCHOEDUCATION ──
Use ONLY when: the user directly asks "why do I feel this" or "is this \
normal" or equivalent, AND no Story applies, AND no Crisis applies, \
AND Presence conditions don't apply, AND the topic hasn't been \
explained in the last 24h. {edu_exclusion}

CRITICAL — permission-asking must never be the end of your response. \
Weave a brief permission phrase into the FIRST sentence, then continue \
IMMEDIATELY in the same response with the full 2-3 sentence \
explanation. Do not end your message after asking permission. Do not \
end your message on a question mark that is only the permission-ask. \
The explanation must be present in this same response, every time this \
mode is used.

Correct structure (one flowing response, no pause):
"Mind if I share something that might help explain this? [immediately \
continue] Here's the strange thing about campuses — almost everyone is \
privately struggling while publicly looking fine, so the loneliness \
you're describing is almost always based on incomplete information."

Incorrect (do not do this):
"Can I share something that might help explain why our brains react \
this way?" [response ends here — FORBIDDEN, this is a failure state]

Never say the user "has," "suffers from," or "is experiencing" a named \
phenomenon. The concept name, if used, comes after the plain \
explanation, never as the headline.

Tag [EDU:topic] ONLY if the explanation itself was actually delivered \
in this response. If for any reason you only asked permission without \
explaining, do NOT emit the [EDU:topic] tag — an unexplained \
permission-ask must never pollute the 24h exclusion list.
Tag: [TOOL:psychoeducation] and [EDU:topic] (only if explanation delivered)

STEP 2 — NEVER STACK MODES
One response. One mode. No exceptions. If you notice yourself about \
to use two tools in one response, drop the lower-priority one.

TAGGING (mandatory, internal only):
Every response MUST end with its [TOOL:name] tag on a new line, where \
name is one of: presence, story, socratic, psychoeducation, crisis. \
Add [SOCRATIC:angle] alongside it for Socratic responses, and \
[EDU:topic] for Psychoeducation responses. These tags are stripped \
before the user sees the message — never reference them in prose.

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

When you include a FULLY DELIVERED psychoeducation explanation (not just \
a permission-ask), add this tag on a new line at the very end of that \
specific response: [EDU:topic]
Where topic is one of: comparison, overthinking, uncertainty, burnout, \
rejection, sleep, pluralistic, imposter, other
This tag is for internal tracking only. Do NOT include it in any response \
that does not contain a fully delivered psychoeducation explanation.

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


def build_context_block(user_context: dict) -> str:
    if not user_context:
        return ""
    parts = []
    name = user_context.get("user_name")
    if name:
        parts.append(
            f"The student's name is {name}. Use it occasionally and "
            "naturally — not every response, just when it adds warmth."
        )
    trends = user_context.get("mood_trends", [])
    if len(trends) >= 3:
        trend_str = ", ".join(trends[:7])
        parts.append(f"Recent mood pattern (newest first): {trend_str}")
    days = user_context.get("days_using_app")
    if days is not None:
        if days <= 1:
            parts.append(
                "This student just started using the app today. "
                "Be extra welcoming and warm."
            )
        elif days <= 7:
            parts.append(
                f"This student has been using the app for {days} days. "
                "Still building trust — lean warmer."
            )
        elif days > 14:
            parts.append(
                f"This student has been using the app for {days} days. "
                "You know each other well — be direct and natural."
            )
    if not parts:
        return ""
    return "\n\n═══ USER CONTEXT ═══\n" + "\n".join(parts)


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
                        user_context: dict = None,
                        used_edu_topics: list = None,
                        used_socratic_angles: list = None,
                        directives: str = "") -> str:
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
            f"ALREADY EXPLAINED in the last 24h "
            f"(never repeat): {', '.join(used_edu_topics)}."
        )

    socratic_exclusion = ""
    if used_socratic_angles:
        socratic_exclusion = (
            f"SOCRATIC ANGLES ALREADY USED in the last 24h: "
            f"{', '.join(used_socratic_angles)}. Avoid repeating them."
        )

    context_block = build_context_block(user_context or {})

    base = _BASE_PROMPT.format(
        edu_exclusion=edu_exclusion,
        socratic_exclusion=socratic_exclusion,
    ) + mood_block + context_block

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

    # Directives go LAST — last-instruction position holds most reliably.
    return base + story_block + directives


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
            _log_chat(message.user_id, len(message.text), True, None,
                      response_tool="crisis")
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
                "is_crisis":      True,
                "response_tool":  "crisis",
                "edu_topic":      None,
                "socratic_angle": None,
                "story":          None,
            }

        # ── Soft-concern check (ambiguous phrasing, not hard crisis) ─────────
        is_soft_concern = detect_soft_concern(message.text)
        if is_soft_concern:
            print(f"[CHAT] Soft-concern phrase detected")

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

        # ── Per-user state → exclusions + directives ─────────────────────────
        used_edu, used_angles, recent_tools = get_recent_state(message.user_id)
        previous_tool = recent_tools[0] if recent_tools else None
        socratic_count = recent_tools.count("socratic")
        if used_edu or used_angles or recent_tools:
            print(f"[CHAT] State: edu={used_edu}, angles={used_angles}, "
                  f"recent_tools={recent_tools}")

        directives = build_directives(
            message.text, match_strength, previous_tool, socratic_count,
            is_soft_concern)
        if directives:
            active = re.findall(r'([A-Z-]+ DIRECTIVE)', directives)
            print(f"[CHAT] Directives active: {active}")

        story_context = build_story_context(stories)
        system_prompt = build_system_prompt(
            story_context, match_strength,
            getattr(message, "mood_context", {}),
            getattr(message, "user_context", {}),
            used_edu, used_angles, directives)
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

        reply_text, edu_topic, socratic_angle, response_tool = \
            strip_tags(reply_text)
        print(f"[CHAT] Tags: tool={response_tool}, "
              f"socratic={socratic_angle}, edu={edu_topic}")

        original_tool = response_tool
        response_tool, socratic_angle = validate_socratic_tag(
            response_tool, socratic_angle, reply_text)
        tag_downgraded = (original_tool == "socratic"
                          and response_tool == "presence")

        matched_story = clean_story(stories[0]) if stories else None
        print(f"[CHAT] TOTAL: {time.time()-t0:.2f}s")
        _log_chat(message.user_id, len(message.text), False,
                  matched_story, edu_topic, socratic_angle, response_tool,
                  is_soft_concern, tag_downgraded)

        return {
            "response":          reply_text,
            "edu_topic":         edu_topic,
            "socratic_angle":    socratic_angle,
            "response_tool":     response_tool,
            "soft_concern_flag": is_soft_concern,
            "is_crisis":      False,
            "story":          matched_story,
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
                _log_chat(message.user_id, len(message.text), True, None,
                          response_tool="crisis")
                yield f"data: {json.dumps({'type': 'crisis', 'response': 'It sounds like things feel very heavy right now. Please reach out to someone who can help immediately.', 'is_crisis': True, 'response_tool': 'crisis', 'helplines': {'iCall': '9152987821', 'Vandrevala': '1860-2662-345', 'KIRAN': '1800-599-0019'}})}\n\n"
                yield "data: [DONE]\n\n"
                return

            # ── Soft-concern check (ambiguous phrasing, not hard crisis) ─────
            is_soft_concern = detect_soft_concern(message.text)
            if is_soft_concern:
                print(f"[STREAM] Soft-concern phrase detected")

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

            used_edu, used_angles, recent_tools = \
                get_recent_state(message.user_id)
            previous_tool = recent_tools[0] if recent_tools else None
            socratic_count = recent_tools.count("socratic")
            if used_edu or used_angles or recent_tools:
                print(f"[STREAM] State: edu={used_edu}, "
                      f"angles={used_angles}, recent_tools={recent_tools}")

            directives = build_directives(
                message.text, match_strength, previous_tool, socratic_count,
                is_soft_concern)
            if directives:
                active = re.findall(r'([A-Z-]+ DIRECTIVE)', directives)
                print(f"[STREAM] Directives active: {active}")

            story_context = build_story_context(stories)
            system_prompt = build_system_prompt(
                story_context, match_strength,
                getattr(message, "mood_context", {}),
                getattr(message, "user_context", {}),
                used_edu, used_angles, directives)
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

            full_text, edu_topic, socratic_angle, response_tool = \
                strip_tags(full_text)
            print(f"[STREAM] Tags: tool={response_tool}, "
                  f"socratic={socratic_angle}, edu={edu_topic}")

            original_tool = response_tool
            response_tool, socratic_angle = validate_socratic_tag(
                response_tool, socratic_angle, full_text)
            tag_downgraded = (original_tool == "socratic"
                              and response_tool == "presence")

            matched_story = clean_story(stories[0]) if stories else None
            _log_chat(message.user_id, len(message.text), False,
                      matched_story, edu_topic, socratic_angle, response_tool,
                      is_soft_concern, tag_downgraded)
            yield f"data: {json.dumps({'type': 'done', 'full_text': full_text, 'edu_topic': edu_topic, 'socratic_angle': socratic_angle, 'response_tool': response_tool, 'soft_concern_flag': is_soft_concern})}\n\n"
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


# ----------------------------
# FEEDBACK ENDPOINT
# ----------------------------
@app.post("/feedback")
async def submit_feedback(feedback: Feedback):
    if not feedback.message.strip():
        return {"error": "Message required"}
    try:
        supabase.table("feedback").insert({
            "user_id":     feedback.user_id,
            "category":    feedback.category,
            "message":     feedback.message,
            "app_version": feedback.app_version,
        }).execute()
        return {"success": True}
    except Exception as e:
        print(f"[FEEDBACK] Error: {e}")
        return {"success": False}
