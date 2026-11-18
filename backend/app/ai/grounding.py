"""Turns stored course content into the text the model is allowed to answer from."""
import json
import re

from ..errors import ApiError


def load_course(db, models, course_id: str) -> dict:
    row = db.get(models.Course, course_id)
    if row is None or row.body is None:
        raise ApiError(404, "NOT_FOUND", "This course has no content on the server.")
    return json.loads(row.body)


def find_lesson(course: dict, lesson_id: str) -> dict:
    for module in course["modules"]:
        for lesson in module["lessons"]:
            if lesson["id"] == lesson_id:
                return lesson
    raise ApiError(404, "NOT_FOUND", "This lesson is not in the server's version of the course.")


def plain(text: str) -> str:
    return re.sub(r"\s+", " ", text or "").strip()


def block_text(block: dict) -> str:
    kind = block.get("type")
    if kind in ("heading", "text"):
        return block.get("text", "")
    if kind == "code":
        return "```\n" + block.get("code", "") + "\n```"
    if kind == "list":
        return "\n".join("- " + item for item in block.get("items", []))
    if kind == "callout":
        return (block.get("title", "") + ": " + block.get("text", "")).strip(": ")
    if kind == "table":
        rows = [" | ".join(block.get("headers", []))] + [" | ".join(row) for row in block.get("rows", [])]
        return "\n".join(rows)
    if kind == "task":
        return "Task: " + block.get("prompt", "") + ("\n" + block["material"] if block.get("material") else "")
    if kind == "diagram":
        diagram = block.get("diagram", {})
        return "Diagram: " + diagram.get("title", "") + ". " + diagram.get("caption", "")
    return ""


def lesson_context(course: dict, lesson: dict, limit: int = 60000) -> str:
    """Every block with its index in square brackets, so the model can say which ones it used."""
    lines = [f"COURSE: {course['title']}", f"LESSON: {lesson['title']}", ""]
    for index, block in enumerate(lesson["blocks"]):
        text = block_text(block)
        if text:
            lines.append(f"[{index}] ({block.get('type')}) {text}")
    return "\n".join(lines)[:limit]


def section_title(lesson: dict, index: int) -> str:
    """The nearest heading at or above the block, or the start of the block itself."""
    blocks = lesson["blocks"]
    for i in range(min(index, len(blocks) - 1), -1, -1):
        if blocks[i].get("type") == "heading":
            return plain(blocks[i].get("text", ""))[:80]
    return plain(block_text(blocks[index]))[:80] if 0 <= index < len(blocks) else ""


def find_task(course: dict, task_id: str) -> tuple[dict, dict]:
    for module in course["modules"]:
        for lesson in module["lessons"]:
            for block in lesson["blocks"]:
                if block.get("type") == "task" and block.get("id") == task_id:
                    return lesson, block
    raise ApiError(404, "NOT_FOUND", "This task is not in the server's version of the course.")


def find_question(course: dict, question_id: str) -> dict:
    for question in course.get("questions", []):
        if question.get("id") == question_id:
            return question
    raise ApiError(404, "NOT_FOUND", "This question is not in the server's version of the course.")


def parse_json_object(text: str) -> dict:
    """The model is asked for one JSON object; tolerate a code fence or a sentence around it."""
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end <= start:
        raise ApiError(502, "AI_FAILED", "The AI answer could not be read. Try again.")
    try:
        value = json.loads(text[start:end + 1])
    except json.JSONDecodeError as exc:
        raise ApiError(502, "AI_FAILED", "The AI answer could not be read. Try again.") from exc
    if not isinstance(value, dict):
        raise ApiError(502, "AI_FAILED", "The AI answer could not be read. Try again.")
    return value
