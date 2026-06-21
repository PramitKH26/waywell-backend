# Waywell

> A peer-story-based mental wellness platform 
> for Indian engineering college students.
> Not therapy. A bridge to it.

## What it is

Waywell helps engineering students navigate 
placement anxiety, academic pressure, and 
loneliness by connecting them — through 
AI-powered conversations — to real, consented 
stories from alumni who lived through the 
same struggles.

When a student shares how they feel, a RAG 
pipeline retrieves the most semantically 
relevant alumni story and Gemini 2.5 Flash 
responds warmly, weaving that lived experience 
into the conversation naturally.

## Tech Stack

**Backend**
- Python / FastAPI
- Google Gemini 2.5 Flash (streaming via SSE)
- Gemini embedding-001 (768-dim vectors)
- Supabase + pgvector (HNSW index)
- Railway (deployment)

**Mobile**
- Flutter (iOS + Android)
- SharedPreferences (local identity + memory)
- flutter_local_notifications

**Architecture**
- RAG pipeline over verified alumni story corpus
- Anonymous UUID identity (no login required)
- Three-tier consent system for story authors
- Server-Sent Events for streaming responses
- Crisis detection with automatic safety routing

## Features

- AI companion chat with real story grounding
- Panic Room (breathing, grounding, helplines)
- Memory Wall (local, private)
- Daily mood check-in
- Scheduled check-in notifications
- Trusted contact alert via WhatsApp

## Status

Closed beta — 50 users at BITS Pilani 
Hyderabad, June 2026.

## Privacy

- Chat message text is never stored server-side
- Anonymous device UUID — no login, no email
- Story authors have explicit tiered consent
- Memory Wall data never leaves the device

## Running Locally

**Backend**
```bash
cd backend
pip install -r requirements.txt
cp .env.example .env   # add your keys
uvicorn main:app --reload
```

**Flutter**
```bash
cd mobile
flutter pub get
flutter run
```

## Environment Variables

See `.env.example` for required keys:
- `GEMINI_API_KEY` — Google AI Studio
- `SUPABASE_URL` — your Supabase project URL
- `SUPABASE_KEY` — Supabase service role key

## Built by

Pramit Khandelwal — 2nd year ECE, 
BITS Pilani Hyderabad
