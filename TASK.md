# AI Performance Engineering 2026 - Admission Assignment

## Overview

Build a simple API service that takes a GitHub repository URL and returns a human-readable summary of the project:
- what it does
- what technologies are used
- how it is structured

This task evaluates your ability to work with external APIs, process code repositories, and use LLMs effectively.

## Technical Requirements

- **Language:** Python 3.10+
- **Web framework:** FastAPI or Flask (your choice)
- **LLM:** Nebius Token Factory API or an alternative LLM provider
- **Model choice:** You choose which LLM model to use from available models on Nebius Token Factory or an alternative provider

## Nebius Token Factory

- Sign up at Nebius Token Factory to get access to LLM models.
- After sign-up, you get **$1 in free credits**.
- You need to fill in billing details to receive credits, but you do not need to top up your account.
- Refer to Nebius Token Factory documentation for available models and API usage.
- As an alternative, you may use other LLM providers (for example: OpenAI, Anthropic, Gemini), but free credits are not provided in that case.

## Endpoint

### `POST /summarize`

Accepts a GitHub repository URL, fetches repository contents, and returns an LLM-generated summary.

### Request body

```json
{
  "github_url": "https://github.com/psf/requests"
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `github_url` | string | yes | URL of a public GitHub repository |

### Success response

```json
{
  "summary": "**Requests** is a popular Python library for making HTTP requests...",
  "technologies": ["Python", "urllib3", "certifi"],
  "structure": "The project follows a standard Python package layout with the main source code in `src/requests/`, tests in `tests/`, ..."
}
```

| Field | Type | Description |
|---|---|---|
| `summary` | string | A human-readable description of what the project does |
| `technologies` | string[] | List of main technologies, languages, and frameworks used |
| `structure` | string | Brief description of the project structure |

### Error response

On error, return an appropriate HTTP status code and:

```json
{
  "status": "error",
  "message": "Description of what went wrong"
}
```

## Key Challenges

- Repositories can be large, so you cannot send everything to the LLM.
- Decide which files are important and which should be ignored (for example: binary files, lock files, `node_modules/`, etc.).
- LLM context windows are limited; you need a strategy to fit the most relevant information.
- Consider what gives the best understanding of a project (README, directory tree, key source files, config files).

There is no single correct approach; the goal is to show your reasoning.

## How Your Code Should Run

Your solution will be evaluated by following README instructions. Ensure that:

1. `README.md` contains step-by-step instructions to install dependencies and start the server.
2. Following those instructions starts the server and exposes `POST /summarize`.
3. The endpoint can be tested with:

```bash
curl -X POST http://localhost:8000/summarize \
  -H "Content-Type: application/json" \
  -d '{"github_url":"https://github.com/psf/requests"}'
```

4. LLM API key is configured via `NEBIUS_API_KEY` (or provider-specific env vars such as `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, etc.). Do not hardcode API keys.

If evaluators can follow your README and get a working response, that is sufficient.

## What to Submit

1. Working source code for the API service.
2. `requirements.txt` (or equivalent, e.g. `pyproject.toml`) with all dependencies.
3. `README.md` including:
   - step-by-step setup and run instructions (assume a clean machine with Python installed)
   - which model you chose and why (1-2 sentences is enough)
   - your approach to handling repository contents (what you include, what you skip, and why)

Upload your solution as a zip archive via the Submit tab.

## Evaluation Criteria

Submission is scored on a **10-point scale** across the criteria below. A perfect score is not required to pass; a solid, working solution with thoughtful decisions is expected.

### Blocking criteria

These must be met for submission to be evaluated. If any fail, score is 0:
- The server starts by following the README.
- `POST /summarize` exists and accepts the required request format.
- The endpoint returns a response (not an error) for a valid public GitHub repository.
- Nebius Token Factory (or an alternative provider) API is used for LLM calls.

### Scoring (100 points total)

| Criteria | Points | What we look for |
|---|---:|---|
| Functionality | 20 | Endpoint returns meaningful, accurate summaries for different repositories; response format matches (`summary`, `technologies`, `structure`). |
| Repo processing | 20 | Files are filtered sensibly (skip binary files, lock files, etc.); clear strategy for selecting informative files. |
| Context management | 20 | Handles large repos without crashing or overloading context; strategy for truncation/prioritization/summarization. |
| Prompt engineering | 10 | Prompts are clear and produce structured, useful output. |
| Code quality & error handling | 20 | Readable/organized code; handles edge cases (invalid URL, private repo, empty repo, network errors); API keys not hardcoded. |
| Documentation | 10 | README includes working setup instructions and brief design rationale. |

**Total: 100 points**

Guidance: do not overcomplicate it. A clean, working solution that handles main scenarios well is enough; extra improvements are optional.
