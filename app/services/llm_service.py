import json
import os
import re
import time
from typing import Any

from fastapi import HTTPException
from openai import (
    APIConnectionError,
    APIError,
    APITimeoutError,
    AuthenticationError,
    BadRequestError,
    OpenAI,
    RateLimitError,
)

from app.config import LLM_MAX_RETRIES, LLM_RETRY_BACKOFF, LLM_TIMEOUT
from app.logging_setup import logger
from app.schemas import SummarizeResponse


def extract_json_object(text: str) -> dict[str, Any]:
    text = text.strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    match = re.search(r"\{.*\}", text, re.DOTALL)
    if not match:
        raise ValueError("LLM did not return valid JSON")
    return json.loads(match.group(0))


def _build_llm_client() -> tuple[OpenAI, str, str]:
    nebius_api_key = os.getenv("NEBIUS_API_KEY")
    openai_api_key = os.getenv("OPENAI_API_KEY")
    if not nebius_api_key and not openai_api_key:
        raise HTTPException(
            status_code=500,
            detail="Missing API key. Set OPENAI_API_KEY or NEBIUS_API_KEY.",
        )

    if openai_api_key:
        provider = "openai"
        model = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
        base_url = os.getenv("OPENAI_BASE_URL")
        client = OpenAI(api_key=openai_api_key, base_url=base_url) if base_url else OpenAI(api_key=openai_api_key)
        return client, provider, model

    provider = "nebius"
    model = os.getenv("NEBIUS_MODEL", "meta-llama/Llama-3.3-70B-Instruct")
    base_url = os.getenv("NEBIUS_BASE_URL", "https://api.tokenfactory.nebius.com/v1/")
    return OpenAI(api_key=nebius_api_key, base_url=base_url), provider, model


def _build_prompt(context: dict[str, Any]) -> str:
    return f"""
You are analyzing a GitHub repository and must return strict JSON.

Return exactly this schema:
{{
  "summary": "string",
  "technologies": ["string"],
  "structure": "string"
}}

Guidelines:
- summary: 3-6 sentences, plain English, what the project does and its purpose.
- technologies: list core languages/frameworks/tools from evidence.
- structure: 2-4 sentences describing layout and major directories.
- Do not include markdown fences.

Repository metadata:
- Name: {context['repo_name']}
- Description: {context['description']}
- Stars: {context['stars']}
- Default branch: {context['default_branch']}
- Languages: {', '.join(context['languages'])}
- Tree summary: {context['tree_summary']}

Selected file excerpts:
{context['files_payload']}
""".strip()


def _request_completion(client: OpenAI, provider: str, model: str, prompt: str):
    for attempt in range(1, LLM_MAX_RETRIES + 1):
        try:
            return client.chat.completions.create(
                model=model,
                messages=[
                    {"role": "system", "content": "You are a precise software repository analyst."},
                    {"role": "user", "content": prompt},
                ],
                temperature=0.2,
                timeout=LLM_TIMEOUT,
            )
        except AuthenticationError as exc:
            logger.warning("llm_auth_error provider=%s model=%s detail=%s", provider, model, exc)
            raise HTTPException(status_code=401, detail="LLM authentication failed. Check your API key.") from exc
        except BadRequestError as exc:
            logger.warning("llm_bad_request provider=%s model=%s detail=%s", provider, model, exc)
            raise HTTPException(status_code=502, detail="LLM provider rejected the request payload.") from exc
        except RateLimitError as exc:
            if attempt >= LLM_MAX_RETRIES:
                raise HTTPException(status_code=429, detail="LLM rate limit reached. Please retry later.") from exc
        except APITimeoutError as exc:
            if attempt >= LLM_MAX_RETRIES:
                raise HTTPException(status_code=504, detail="LLM request timed out.") from exc
        except APIConnectionError as exc:
            if attempt >= LLM_MAX_RETRIES:
                raise HTTPException(status_code=502, detail="Unable to connect to LLM provider.") from exc
        except APIError as exc:
            if attempt >= LLM_MAX_RETRIES:
                raise HTTPException(status_code=502, detail="LLM provider returned an upstream error.") from exc
        except Exception as exc:
            logger.exception("llm_unexpected_error provider=%s model=%s", provider, model)
            raise HTTPException(status_code=502, detail="Unexpected LLM request failure.") from exc

        logger.warning("llm_transient_retry provider=%s model=%s attempt=%s/%s", provider, model, attempt, LLM_MAX_RETRIES)
        time.sleep(LLM_RETRY_BACKOFF * attempt)

    raise HTTPException(status_code=502, detail="LLM request failed after retries.")


def generate_summary(context: dict[str, Any]) -> SummarizeResponse:
    client, provider, model = _build_llm_client()
    completion = _request_completion(client, provider, model, _build_prompt(context))

    choices = completion.choices or []
    if not choices:
        raise HTTPException(status_code=502, detail="LLM provider returned no choices.")

    content = choices[0].message.content or ""
    if not content.strip():
        raise HTTPException(status_code=502, detail="LLM provider returned empty content.")

    try:
        parsed = extract_json_object(content)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"LLM response parsing failed: {exc}") from exc

    summary = parsed.get("summary")
    technologies = parsed.get("technologies")
    structure = parsed.get("structure")

    if not isinstance(summary, str) or not isinstance(structure, str):
        raise HTTPException(status_code=502, detail="LLM returned invalid fields for summary/structure")
    if not isinstance(technologies, list) or not all(isinstance(item, str) for item in technologies):
        raise HTTPException(status_code=502, detail="LLM returned invalid technologies list")

    return SummarizeResponse(
        summary=summary.strip(),
        technologies=[item.strip() for item in technologies if item.strip()],
        structure=structure.strip(),
    )
