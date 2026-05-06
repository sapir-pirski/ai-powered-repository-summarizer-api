import time

from fastapi import FastAPI, HTTPException, Request

from app.error_handlers import register_error_handlers
from app.logging_setup import logger
from app.schemas import SummarizeRequest, SummarizeResponse
from app.services.llm_service import generate_summary
from app.services.repository_service import fetch_repo_context, parse_github_url


app = FastAPI(
    title="AI-Powered Repository Summarizer API",
    description="Summarizes public GitHub repositories with an LLM.",
    version="1.0.0",
)
register_error_handlers(app)


@app.middleware("http")
async def log_request_metrics(request: Request, call_next):
    start_time = time.perf_counter()
    try:
        response = await call_next(request)
        duration_ms = (time.perf_counter() - start_time) * 1000
        logger.info(
            "request method=%s path=%s status=%s duration_ms=%.2f",
            request.method,
            request.url.path,
            response.status_code,
            duration_ms,
        )
        return response
    except Exception:
        duration_ms = (time.perf_counter() - start_time) * 1000
        logger.exception(
            "request_failed method=%s path=%s duration_ms=%.2f",
            request.method,
            request.url.path,
            duration_ms,
        )
        raise


@app.post("/summarize", response_model=SummarizeResponse)
def summarize_repo(payload: SummarizeRequest) -> SummarizeResponse:
    logger.info("Summarize request received github_url=%s", payload.github_url)
    try:
        repo_ref = parse_github_url(payload.github_url)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    context = fetch_repo_context(repo_ref)
    if not context["files_payload"].strip():
        raise HTTPException(
            status_code=422,
            detail="No usable text files were found in the repository",
        )

    return generate_summary(context)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
