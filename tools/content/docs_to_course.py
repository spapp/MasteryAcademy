#!/usr/bin/env python3
"""Turns a Claude Docs export into a course fragment (content/sources/<id>.json) that build_content.mjs reads.

  docs_to_course.py md  <export.md>   <course-id> <module title>     Markdown export
  docs_to_course.py pdf <export.pdf>  <course-id> <module title>     PDF export (needs poppler's pdftohtml)

Each "## " section becomes a lesson. The fragment is a snapshot: re-export the doc and re-run to refresh it.
"""
import html, json, os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
slug = lambda s: re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")
words = lambda blocks: len(json.dumps(blocks).split())


def finish(course_id, module_title, lessons, resources):
    out = []
    for title, blocks in lessons:
        if title.lower() == "sources" or not blocks:
            continue
        out.append({"id": f"{course_id}-{slug(title)[:48]}", "title": title, "minutes": max(3, round(words(blocks) / 180)), "level": 0, "blocks": blocks, "quiz": []})
    frag = {"modules": [{"id": f"{course_id}-guide", "title": module_title, "summary": "", "tag": "", "lessons": out}], "questions": [], "resources": resources}
    path = os.path.join(ROOT, "content/sources", course_id + ".json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(frag, open(path, "w"), ensure_ascii=False, indent=1)
    print(course_id, len(out), "lessons,", sum(len(l["blocks"]) for l in out), "blocks,", len(resources), "links ->", os.path.relpath(path, ROOT))


# ---------- Markdown ----------
def md_inline(s):
    s = re.sub(r"\[([^\]]+)\]\((https?://[^)]+)\)", r"\1", s)
    s = html.unescape(s).replace("\\]", "]").replace("\\[", "[").replace("\\|", "|")
    return s.strip()


def from_markdown(path):
    lines = open(path, encoding="utf8").read().split("\n")
    lessons, resources, cur, i = [], [], None, 0
    para = []

    def flush():
        if para and cur is not None:
            cur[1].append({"type": "text", "text": md_inline(" ".join(para))})
        para.clear()

    while i < len(lines):
        line = lines[i]
        for t, u in re.findall(r"\[([^\]]+)\]\((https?://[^)]+)\)", line):
            resources.append({"title": t, "kind": "Link", "url": u})
        if line.startswith("## "):
            flush(); cur = (md_inline(line[3:]), []); lessons.append(cur)
        elif cur is None:
            pass
        elif line.startswith("### ") or line.startswith("#### "):
            flush(); cur[1].append({"type": "heading", "text": md_inline(line.lstrip("# "))})
        elif line.startswith("```"):
            flush(); lang = line[3:].strip() or "text"; body = []; i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                body.append(lines[i]); i += 1
            cur[1].append({"type": "code", "code": "\n".join(body).rstrip(), "language": lang})
        elif line.startswith("|"):
            flush(); rows = []
            while i < len(lines) and lines[i].startswith("|"):
                cells = [md_inline(c) for c in re.split(r"(?<!\\)\|", lines[i].strip().strip("|"))]
                if not all(re.fullmatch(r":?-+:?", c.strip()) for c in cells):
                    rows.append(cells)
                i += 1
            i -= 1
            if len(rows) > 1:
                w = max(len(r) for r in rows); pad = lambda r: r + [""] * (w - len(r))
                cur[1].append({"type": "table", "headers": pad(rows[0]), "rows": [pad(r) for r in rows[1:]]})
        elif re.match(r"\s*([-*]|\d+\.)\s", line):
            flush(); ordered = bool(re.match(r"\s*\d+\.", line)); items = []
            while i < len(lines) and (re.match(r"\s*([-*]|\d+\.)\s", lines[i]) or (lines[i].startswith("  ") and lines[i].strip())):
                m = re.match(r"\s*([-*]|\d+\.)\s+(\[[ x]\]\s+)?(.*)", lines[i])
                if m: items.append(md_inline(m.group(3)))
                elif items: items[-1] += " " + md_inline(lines[i])
                i += 1
            i -= 1
            cur[1].append({"type": "list", "ordered": ordered, "items": items})
        elif not line.strip():
            flush()
        else:
            para.append(line.strip())
        i += 1
    flush()
    seen, uniq = set(), []
    for r in resources:
        if r["url"] not in seen: seen.add(r["url"]); uniq.append(r)
    return lessons, uniq


# ---------- PDF (pdftohtml -xml) ----------
H2, CODE, TABLE, MONO, BOLD, SKIP = {3}, {12, 13}, {6, 7, 8, 15, 17, 18}, {8, 10, 14}, {5, 14}, {0, 1, 9}


def from_pdf(path):
    tmp = os.path.join(tempfile.mkdtemp(), "x")
    subprocess.run(["pdftohtml", "-xml", "-i", "-q", path, tmp], check=True)
    xml = open(tmp + ".xml", encoding="utf8").read()
    items, resources = [], []
    for pno, page in enumerate(re.findall(r"<page [^>]*>(.*?)</page>", xml, re.S)):
        for top, left, font, text in re.findall(r'<text top="(\d+)" left="(\d+)"[^>]*font="(\d+)">(.*?)</text>', page, re.S):
            font, top = int(font), int(top)
            if font in SKIP or top < 60: continue
            for u, t in re.findall(r'<a href="(https?://[^"]+)">(.*?)</a>', text): resources.append({"title": html.unescape(re.sub(r"<[^>]+>", "", t)), "kind": "Link", "url": u})
            plain = html.unescape(re.sub(r"<[^>]+>", "", text))
            if plain.strip() or font in CODE: items.append([pno * 10000 + top, int(left), font, plain])
    items.sort(key=lambda t: (t[0], t[1]))
    lines = []
    for it in items:
        if lines and abs(it[0] - lines[-1][0][0]) <= 6: lines[-1].append(it)
        else: lines.append([it])
    for ln in lines: ln.sort(key=lambda t: t[1])
    fmt = lambda it: ("`%s`" % it[3].strip() if it[2] in MONO and it[3].strip() else "**%s**" % it[3].strip() if it[2] in BOLD and it[3].strip() else it[3])
    join = lambda its: re.sub(r"(\w)- (\w)", r"\1-\2", re.sub(r"\s+([,.;:)])", r"\1", re.sub(r"\s+", " ", " ".join(fmt(i) for i in its)))).strip()
    lessons, cur, k = [], None, 0
    while k < len(lines):
        ln = lines[k]; fonts = {i[2] for i in ln}
        if fonts & H2:
            cur = (join(ln), []); lessons.append(cur); k += 1; continue
        if cur is None: k += 1; continue
        if fonts <= CODE:
            body, prev = [], None
            while k < len(lines) and {i[2] for i in lines[k]} <= CODE and (prev is None or lines[k][0][0] - prev < 60 or lines[k][0][0] // 10000 != prev // 10000):
                row = ""
                for it in lines[k]:
                    col = max(len(row), round((it[1] - 94) / 9.6)); row = row.ljust(col) + it[3]
                body.append(row.rstrip()); prev = lines[k][0][0]; k += 1
            cur[1].append({"type": "code", "code": "\n".join(body).rstrip(), "language": "kotlin" if re.search(r"\b(fun|val|class|kotlin)\b", "\n".join(body)) else "text"})
            continue
        if fonts & TABLE and not fonts & {2}:
            tl = []
            while k < len(lines) and {i[2] for i in lines[k]} & TABLE and not {i[2] for i in lines[k]} & {2, 3}: tl.append(lines[k]); k += 1
            head_fonts = {6, 17}
            cols = sorted({i[1] for l in tl for i in l if i[2] in head_fonts})
            merged = []
            for c in cols:
                if not merged or c - merged[-1] > 40: merged.append(c)
            cols = merged or [tl[0][0][1]]
            first = min(i[1] for l in tl for i in l)
            if first < cols[0] - 40: cols.insert(0, first)   # header cell of the first column is empty
            tops = [l[0][0] for l in tl]
            gaps = [b - a for a, b in zip(tops, tops[1:]) if 0 < b - a < 200]
            row_gap = (min(gaps) if gaps else 24) * 1.3
            col_of = lambda left: max([n for n, c in enumerate(cols) if c <= left + 8] or [0])
            rows, prev, prev_head = [], None, None
            for l in tl:
                is_head = all(i[2] in head_fonts for i in l)
                new = prev is None or l[0][0] - prev > row_gap or l[0][0] // 10000 != prev // 10000 and is_head or is_head != prev_head
                if new: rows.append([is_head, [[] for _ in cols]])
                for it in l: rows[-1][1][col_of(it[1])].append(it)
                prev, prev_head = l[0][0], is_head
            table = [(h, [join(c) for c in cells]) for h, cells in rows]
            header = next((c for h, c in table if h), [""] * len(cols))
            if len(cols) > len([c for c in header if c]) and not header[-1]: header = [""] + header[:-1]
            body = [c for h, c in table if not h]
            # a row split by a page break continues in the next row when its first cell is empty
            fixed = []
            for r in body:
                if fixed and not r[0] and any(r): fixed[-1] = [(a + " " + b).strip() for a, b in zip(fixed[-1], r)]
                else: fixed.append(r)
            if fixed: cur[1].append({"type": "table", "headers": header, "rows": fixed})
            continue
        # body text and list items
        is_item = ln[0][1] >= 105
        text, prev = [join(ln)], ln[0][0]; k += 1
        while k < len(lines):
            n = lines[k]; nf = {i[2] for i in n}
            if nf & (H2 | CODE) or (nf & TABLE and not nf & {2}) or (n[0][1] >= 105) != is_item: break
            if n[0][0] - prev > 30 and n[0][0] // 10000 == prev // 10000: break
            text.append(join(n)); prev = n[0][0]; k += 1
        t = re.sub(r"\s+", " ", " ".join(text)).replace("- ", "-") if False else re.sub(r"\s+", " ", " ".join(text))
        t = re.sub(r"(\w)- (\w)", r"\1-\2", t)
        if is_item and cur[1] and cur[1][-1]["type"] == "list": cur[1][-1]["items"].append(t)
        elif is_item: cur[1].append({"type": "list", "ordered": False, "items": [t]})
        else: cur[1].append({"type": "text", "text": t})
    seen, uniq = set(), []
    for r in resources:
        if r["url"] not in seen: seen.add(r["url"]); uniq.append(r)
    return lessons, uniq


if __name__ == "__main__":
    kind, src, course_id, module_title = sys.argv[1:5]
    lessons, resources = (from_markdown if kind == "md" else from_pdf)(src)
    finish(course_id, module_title, lessons, resources)
