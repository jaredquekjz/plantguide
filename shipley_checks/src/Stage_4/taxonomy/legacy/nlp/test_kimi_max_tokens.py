#!/usr/bin/env python3
"""Test kimi-k2-thinking with different max_tokens values"""
import os
import asyncio
from openai import AsyncOpenAI

API_KEY = os.getenv("MOONSHOT_API_KEY")

async def test_max_tokens(max_tokens_value):
    client = AsyncOpenAI(
        api_key=API_KEY,
        base_url="https://api.moonshot.ai/v1"
    )

    prompt = """Based on the vernacular names provided, identify what TYPE of organism this is and output a GENERIC CATEGORY label.

IMPORTANT: We need a category for grouping in reports (e.g., "25% Bees, 30% Butterflies").
- Output the ORGANISM TYPE, not specific names
- Example: "duckweed weevil" → output "Weevils" (NOT "Duckweed weevil")

Rules:
- Use the most common/obvious organism type from the English names
- Always use plural form (e.g., "Aphids", "Beetles", "Bees", "Moths", "Butterflies")
- Keep it simple and generic (1-2 words max)
- Output ONLY in English, even if Chinese names are provided

Genus: Tanysphyrus
English names: duckweed weevil
Chinese names: 浮萍小象

Output ONLY the generic category, nothing else."""

    response = await client.chat.completions.create(
        model="kimi-k2-thinking",
        messages=[
            {"role": "system", "content": "You are a gardening expert. Provide concise, clear common names."},
            {"role": "user", "content": prompt}
        ],
        temperature=0.3,
        max_tokens=max_tokens_value
    )

    print(f"\n{'='*80}")
    print(f"max_tokens={max_tokens_value}")
    print(f"{'='*80}")
    print(f"Finish reason: {response.choices[0].finish_reason}")
    print(f"Tokens used: {response.usage.completion_tokens}/{max_tokens_value}")
    print(f"\nReasoning content: '{response.choices[0].message.reasoning_content[:200] if response.choices[0].message.reasoning_content else None}...'")
    print(f"\nActual content: '{response.choices[0].message.content}'")
    print(f"Cleaned: '{response.choices[0].message.content.strip()}'")

async def main():
    print("Testing kimi-k2-thinking with different max_tokens values")

    for max_tokens in [20, 50, 100, 200, 500]:
        await test_max_tokens(max_tokens)

    await asyncio.sleep(1)  # Give time for cleanup

asyncio.run(main())
