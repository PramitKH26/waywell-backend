"""
One-time seeding script for real stories.
Reads from stories_seed.json, generates embeddings, inserts into Supabase.
Idempotent — skips stories whose author_name already exists in the content.

Usage:  python3 scripts/seed_real_stories.py
"""

import json
import os
import sys

from dotenv import load_dotenv
import google.genai as genai
from supabase import create_client

# Load env from project root
load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))
supabase = create_client(os.getenv("SUPABASE_URL"), os.getenv("SUPABASE_KEY"))

SEED_FILE = os.path.join(os.path.dirname(__file__), "..", "stories_seed.json")


def build_content(story: dict) -> str:
    """Flatten the story into a single content string for storage + retrieval."""
    parts = [
        f"Author: {story['author_name']}, {story['college']} ({story['grad_year']})",
        f"What was hard: {story['what_was_hard']}",
        f"Lowest moment: {story['lowest_moment']}",
        f"What helped: {story['what_helped']}",
        f"Where they are now: {story['where_now']}",
        f"One wish: {story['one_wish']}",
        f"Categories: {', '.join(story['categories'])}",
    ]
    return "\n".join(parts)


def build_embedding_text(story: dict) -> str:
    """Concatenate the three key fields for embedding (per spec)."""
    return "\n".join([
        story["what_was_hard"],
        story["what_helped"],
        story["where_now"],
    ])


def get_embedding(text: str) -> list[float]:
    response = client.models.embed_content(
        model="gemini-embedding-001",
        contents=text,
        config={"output_dimensionality": 768},
    )
    return response.embeddings[0].values


def author_exists(author_name: str) -> bool:
    """Check if a story with this author_name is already in the table."""
    result = (
        supabase.table("stories")
        .select("id")
        .ilike("content", f"%Author: {author_name},%")
        .execute()
    )
    return len(result.data) > 0


def seed():
    with open(SEED_FILE, "r") as f:
        stories = json.load(f)

    print(f"Found {len(stories)} stories in seed file.\n")

    for story in stories:
        name = story["author_name"]

        if author_exists(name):
            print(f"Skipped: {name} (already exists)")
            continue

        content = build_content(story)
        embed_text = build_embedding_text(story)
        embedding = get_embedding(embed_text)

        supabase.table("stories").insert({
            "content": content,
            "embedding": embedding,
        }).execute()

        print(f"Inserted: {name}")

    print("\nSeeding complete.")


def test_rag():
    """Run 3 test queries and verify the top match."""
    tests = [
        ("I can't leave my room I haven't eaten in days", "Aman"),
        ("I had surgery during exams it was terrifying", "Srijan"),
        ("I'm in first year and I have no friends", "Akhil"),
    ]

    print("\n── RAG Verification ─────────────────────────────────\n")

    all_passed = True
    for query, expected in tests:
        embedding = get_embedding(query)
        result = supabase.rpc("match_stories", {
            "query_embedding": embedding,
            "match_count": 1,
        }).execute()

        if result.data:
            top_content = result.data[0]["content"]
            # Extract author name from the content string
            author_line = top_content.split("\n")[0]  # "Author: Aman, BITS Pilani (2017)"
            matched_name = author_line.split("Author: ")[1].split(",")[0]

            if matched_name == expected:
                print(f"  ✅ \"{query}\"")
                print(f"     → {matched_name} (correct)\n")
            else:
                print(f"  ❌ \"{query}\"")
                print(f"     → Expected {expected}, got {matched_name}\n")
                all_passed = False
        else:
            print(f"  ❌ \"{query}\"")
            print(f"     → No results returned\n")
            all_passed = False

    if all_passed:
        print("All 3 tests passed. RAG is working correctly.")
    else:
        print("Some tests failed — check above.")


if __name__ == "__main__":
    seed()
    test_rag()
