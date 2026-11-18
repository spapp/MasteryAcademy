import uuid

from fastapi import FastAPI, Request

from . import errors
from .generated.operations import BASE_PATH
from .routers import ai, auth, content, ops, progress


def create_app() -> FastAPI:
    app = FastAPI(title="Mastery Academy API", version="1.0.0", docs_url="/docs", openapi_url="/openapi.json",
                  generate_unique_id_function=lambda route: route.name)  # operationId = handler name = spec operation id
    errors.install(app)

    @app.middleware("http")
    async def request_id(request: Request, call_next):
        request.state.request_id = request.headers.get("x-request-id") or uuid.uuid4().hex
        response = await call_next(request)
        response.headers["X-Request-Id"] = request.state.request_id
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response

    for r in (ops.router, auth.router, content.router, progress.router, ai.router):
        app.include_router(r, prefix=BASE_PATH)
    return app


app = create_app()
