"""One error envelope for every failure: {"error": {"code", "message", "requestId", "fields"?}}."""
from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str, fields: dict | None = None):
        self.status, self.code, self.message, self.fields = status, code, message, fields


def _body(request: Request, code: str, message: str, fields: dict | None = None) -> dict:
    err = {"code": code, "message": message, "requestId": getattr(request.state, "request_id", "")}
    if fields:
        err["fields"] = fields
    return {"error": err}


# Phase 2 adds AI_DISABLED (503), LIMIT_REACHED (429) and AI_FAILED (502); they are raised as ApiError.
STATUS_CODES = {401: "UNAUTHENTICATED", 403: "FORBIDDEN", 404: "NOT_FOUND", 405: "NOT_FOUND", 409: "CONFLICT", 429: "RATE_LIMITED", 501: "NOT_IMPLEMENTED"}


def install(app):
    @app.exception_handler(ApiError)
    async def _api(request: Request, exc: ApiError):
        return JSONResponse(_body(request, exc.code, exc.message, exc.fields), status_code=exc.status)

    @app.exception_handler(RequestValidationError)
    async def _validation(request: Request, exc: RequestValidationError):
        fields = {".".join(str(p) for p in e["loc"][1:]) or str(e["loc"][0]): e["msg"] for e in exc.errors()}
        return JSONResponse(_body(request, "VALIDATION_FAILED", "The request is not valid.", fields), status_code=422)

    @app.exception_handler(StarletteHTTPException)
    async def _http(request: Request, exc: StarletteHTTPException):
        code = STATUS_CODES.get(exc.status_code, "INTERNAL")
        return JSONResponse(_body(request, code, str(exc.detail)), status_code=exc.status_code)

    @app.exception_handler(Exception)
    async def _unhandled(request: Request, exc: Exception):
        return JSONResponse(_body(request, "INTERNAL", "Something went wrong."), status_code=500)
