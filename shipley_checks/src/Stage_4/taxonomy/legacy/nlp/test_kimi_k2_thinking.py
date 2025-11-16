#!/usr/bin/env python3
"""
Test kimi-k2-thinking model response format
"""
import os
from openai import OpenAI
import asyncio
from openai import AsyncOpenAI

API_KEY = os.getenv("MOONSHOT_API_KEY")
if not API_KEY:
    print("ERROR: MOONSHOT_API_KEY not set!")
    exit(1)

print("=" * 80)
print("Testing kimi-k2-thinking Model")
print("=" * 80)

# ============================================================================
# Test 1: Synchronous + Streaming (from your example)
# ============================================================================

print("\n[Test 1] Synchronous client + streaming")
print("-" * 80)

client = OpenAI(
    api_key=API_KEY,
    base_url="https://api.moonshot.ai/v1"
)

try:
    response = client.chat.completions.create(
        model="kimi-k2-thinking",
        messages=[
            {
                "role": "system",
                "content": "You are a helpful assistant."
            },
            {
                "role": "user",
                "content": "hello"
            },
            {
                "role": "assistant",
                "content": "Hello! How can I help you today?"
            },
            {
                "role": "user",
                "content": "are u from China?"
            },
            {
                "role": "assistant",
                "content": "I'm an AI assistant developed by Moonshot AI (月之暗面科技有限公司), which is a Chinese company. So yes, I have Chinese origins, though as an AI, I don't have a personal nationality or physical location. How can I help you?"
            }
        ],
        temperature=1,
        max_tokens=32768,
        top_p=1,
        stream=True
    )

    # Handle streaming response
    print("Response: ", end="")
    for chunk in response:
        if chunk.choices[0].delta.content is not None:
            print(chunk.choices[0].delta.content, end="")
    print()
    print("✓ Test 1 passed")

except Exception as e:
    print(f"✗ Test 1 failed: {e}")

# ============================================================================
# Test 2: Synchronous + Non-streaming
# ============================================================================

print("\n[Test 2] Synchronous client + non-streaming")
print("-" * 80)

try:
    response = client.chat.completions.create(
        model="kimi-k2-thinking",
        messages=[
            {
                "role": "system",
                "content": "You are a gardening expert. Provide concise, clear common names."
            },
            {
                "role": "user",
                "content": "What type of organism is a 'duckweed weevil'? Output only the category (e.g., Weevils, Beetles, Bees)."
            }
        ],
        temperature=0.3,
        max_tokens=20,
        stream=False
    )

    print(f"Full response object: {response}")
    print(f"\nContent: '{response.choices[0].message.content}'")
    print(f"Finish reason: {response.choices[0].finish_reason}")
    print("✓ Test 2 passed")

except Exception as e:
    print(f"✗ Test 2 failed: {e}")

# ============================================================================
# Test 3: Async + Non-streaming (what our scripts use)
# ============================================================================

print("\n[Test 3] Async client + non-streaming")
print("-" * 80)

async def test_async():
    async_client = AsyncOpenAI(
        api_key=API_KEY,
        base_url="https://api.moonshot.ai/v1"
    )

    try:
        response = await async_client.chat.completions.create(
            model="kimi-k2-thinking",
            messages=[
                {
                    "role": "system",
                    "content": "You are a gardening expert. Provide concise, clear common names."
                },
                {
                    "role": "user",
                    "content": "What type of organism is a 'duckweed weevil'? Output only the category (e.g., Weevils, Beetles, Bees)."
                }
            ],
            temperature=0.3,
            max_tokens=20
        )

        print(f"Full response object: {response}")
        print(f"\nContent: '{response.choices[0].message.content}'")
        print(f"Finish reason: {response.choices[0].finish_reason}")
        print("✓ Test 3 passed")

    except Exception as e:
        print(f"✗ Test 3 failed: {e}")

asyncio.run(test_async())

# ============================================================================
# Test 4: Async + Non-streaming with our actual prompt
# ============================================================================

print("\n[Test 4] Async client with our categorization prompt")
print("-" * 80)

async def test_categorization():
    async_client = AsyncOpenAI(
        api_key=API_KEY,
        base_url="https://api.moonshot.ai/v1"
    )

    prompt = """Based on the vernacular names provided, identify what TYPE of organism this is and output a GENERIC CATEGORY label.

IMPORTANT: We need a category for grouping in reports (e.g., "25% Bees, 30% Butterflies").
- Output the ORGANISM TYPE, not specific names
- Example: "duckweed weevil" → output "Weevils" (NOT "Duckweed weevil")
- Example: "carpenter bee" → output "Bees" (NOT "Carpenter bees")
- Example: "garden tiger moth" → output "Moths" (NOT "Garden tiger moth")

Rules:
- Use the most common/obvious organism type from the English names
- Always use plural form (e.g., "Aphids", "Beetles", "Bees", "Moths", "Butterflies")
- Keep it simple and generic (1-2 words max)
- Output ONLY in English, even if Chinese names are provided

Genus: Tanysphyrus
English names: duckweed weevil
Chinese names: 浮萍小象

Output ONLY the generic category, nothing else."""

    try:
        response = await async_client.chat.completions.create(
            model="kimi-k2-thinking",
            messages=[
                {
                    "role": "system",
                    "content": "You are a gardening expert. Provide concise, clear common names."
                },
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            temperature=0.3,
            max_tokens=20
        )

        print(f"Full response object: {response}")
        print(f"\nContent: '{response.choices[0].message.content}'")
        print(f"Finish reason: {response.choices[0].finish_reason}")

        label = response.choices[0].message.content.strip()
        label = label.strip('."\'')
        print(f"Cleaned label: '{label}'")
        print("✓ Test 4 passed")

    except Exception as e:
        print(f"✗ Test 4 failed: {e}")

asyncio.run(test_categorization())

print("\n" + "=" * 80)
print("All tests complete")
print("=" * 80)
