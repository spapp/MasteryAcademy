"""The one place that talks to the Claude API. Tests replace `complete`."""
import httpx

from ..config import get_settings
from ..errors import ApiError

API_URL = "https://api.anthropic.com/v1/messages"
API_VERSION = "2023-06-01"


def complete(*, model: str, instructions: str, context: str, user: str, max_tokens: int) -> tuple[str, int, int]:
    """Returns (text, input_tokens, output_tokens). `context` (the lesson) is sent as a cached system block,
    so repeated questions on one lesson cost less."""
    settings = get_settings()
    system = [{"type": "text", "text": instructions}]
    if context:
        system.append({"type": "text", "text": context, "cache_control": {"type": "ephemeral"}})
    try:
        response = httpx.post(
            API_URL,
            headers={"x-api-key": settings.anthropic_api_key, "anthropic-version": API_VERSION, "content-type": "application/json"},
            json={"model": model, "max_tokens": max_tokens, "system": system, "messages": [{"role": "user", "content": user}]},
            timeout=60,
        )
    except httpx.HTTPError as exc:
        raise ApiError(502, "AI_FAILED", "Could not reach the AI service. Try again.") from exc
    if response.status_code != 200:
        # The provider's message can name the account; keep it out of the app.
        raise ApiError(502, "AI_FAILED", f"The AI service answered {response.status_code}. Try again later.")
    data = response.json()
    text = "".join(part.get("text", "") for part in data.get("content", []) if part.get("type") == "text")
    usage = data.get("usage", {})
    read = usage.get("input_tokens", 0) + usage.get("cache_creation_input_tokens", 0) + usage.get("cache_read_input_tokens", 0)
    return text, int(read), int(usage.get("output_tokens", 0))
