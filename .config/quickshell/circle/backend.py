#!/usr/bin/env python3
"""Answer engine for the circle overlay — one conversation per process.

    backend.py <provider> <model>     provider: antigravity | claude | gemini | local
    backend.py check                  print which providers are usable (JSON)
    backend.py warm <model>           load a local model into VRAM ahead of a question

stdin:  one JSON object per line: {"text": "...", "image": "/path.png" | null}
stdout: one JSON event per line, the same for every provider:
    {"t": "status", "v": "Searching the web"}   transient progress line
    {"t": "reset"}                              drop text streamed so far
    {"t": "delta", "v": "..."}                  answer text
    {"t": "done"}                               turn finished
    {"t": "error", "v": "..."}                  turn failed
    {"t": "conv", "v": "<id>"}                  antigravity only: the agy conversation,
                                                for "Continue in Antigravity"

Standard library only. Everything that leaves the machine is in this file or
circle.sh.
"""

import base64
import html
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SYSTEM = open(os.path.join(HERE, "system-prompt.md"), encoding="utf-8").read()
CONF = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "circle")
GEMINI_KEY_FILE = os.path.join(CONF, "gemini-key")
AGY_DIR = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "circle", "agy")
AGY_HOME = os.path.expanduser("~/.gemini/antigravity-cli")
AGY_KEEP_DAYS = 3
STATE = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "circle")
# Appended to system-prompt.md as the agy workspace's GEMINI.md.
AGY_RULES = """
## This session

- A question may start with "[Screen selection: ./sel-….png]". That image is
  what the user circled: open it with your file viewer before answering. To the
  user it is just "the selection" — never mention, link or cite the file, its
  name or its path.
- Your web tools are search_web and read_url_content.
- You have no terminal and no other files. Never try to run commands, write
  files, or make plans, tasks or artifacts — just answer.
"""
OLLAMA = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434").rstrip("/")
# Same for questions and warm-up — a different num_ctx makes Ollama reload the model.
LOCAL_OPTS = {"num_ctx": 16384}
LOCAL_KEEP = "10m"   # then the model leaves VRAM (games get it back)
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140 Safari/537.36"


def emit(t, v=None):
    ev = {"t": t} if v is None else {"t": t, "v": v}
    sys.stdout.write(json.dumps(ev) + "\n")
    sys.stdout.flush()


def image_png(path, max_side=1568):
    """Downscaled PNG bytes — models resize past ~1.5k px anyway."""
    if not path or not os.path.isfile(path):
        return None
    out = subprocess.run(["magick", path, "-resize", f"{max_side}x{max_side}>", "png:-"],
                         capture_output=True)
    return out.stdout if out.returncode == 0 else open(path, "rb").read()


def http_json(url, body=None, headers=None, timeout=60):
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json", **(headers or {})})
    return urllib.request.urlopen(req, timeout=timeout)


def http_error(e):
    try:
        body = json.loads(e.read().decode())
        return body.get("error", {}).get("message") or body.get("error") or str(e)
    except Exception:
        return str(e)


# ---- web tools (used by the local model) ---------------------------------

def web_search(query, n=6):
    url = "https://html.duckduckgo.com/html/?" + urllib.parse.urlencode({"q": query})
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    page = urllib.request.urlopen(req, timeout=15).read().decode("utf-8", "replace")
    results = []
    for m in re.finditer(r'class="result__a" href="([^"]+)"[^>]*>(.*?)</a>.*?class="result__snippet"[^>]*>(.*?)</a>',
                         page, re.S):
        href, title, snippet = m.groups()
        q = urllib.parse.parse_qs(urllib.parse.urlparse(html.unescape(href)).query)
        link = q.get("uddg", [html.unescape(href)])[0]
        strip = lambda s: html.unescape(re.sub(r"<[^>]+>", "", s)).strip()
        results.append(f"- {strip(title)} — {link}\n  {strip(snippet)}")
        if len(results) >= n:
            break
    return "\n".join(results) or "No results."


def fetch_page(url, limit=6000):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    raw = urllib.request.urlopen(req, timeout=15).read(800_000).decode("utf-8", "replace")
    raw = re.sub(r"(?is)<(script|style|noscript|svg|nav|footer|header)[^>]*>.*?</\1>", " ", raw)
    text = html.unescape(re.sub(r"<[^>]+>", " ", raw))
    return re.sub(r"\s+", " ", text).strip()[:limit]


TOOLS = [
    {"type": "function", "function": {
        "name": "web_search",
        "description": "Search the web. Use for anything current or factual you are not sure about.",
        "parameters": {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]}}},
    {"type": "function", "function": {
        "name": "fetch_page",
        "description": "Read the text of a web page found with web_search.",
        "parameters": {"type": "object", "properties": {"url": {"type": "string"}}, "required": ["url"]}}},
]


def run_tool(name, args):
    try:
        if name == "web_search":
            emit("status", "Searching the web")
            return web_search(args.get("query", ""))
        if name == "fetch_page":
            emit("status", "Reading")
            return fetch_page(args.get("url", ""))
    except Exception as e:
        return f"Tool failed: {e}"
    return f"Unknown tool {name}"


# ---- providers -----------------------------------------------------------

class Antigravity:
    """Gemini on the user's Google AI Pro plan, through the Antigravity CLI (agy).

    agy is a coding agent. In print mode anything that needs a permission
    (commands, files outside its folder) is denied, so here it can only open the
    selections put into its folder and use the web. Its stream input takes text
    only, so the image goes in as a file that the prompt points at.

    agy has no --no-session-persistence; conversations started here are pruned
    after AGY_KEEP_DAYS (they hold the screenshots), which leaves a few days to
    pick one up with "Continue in Antigravity"."""

    STATUS = {"search_web": "Searching the web", "read_url_content": "Reading",
              "read_file": "Looking", "view_file": "Looking"}

    def __init__(self, model):
        os.makedirs(AGY_DIR, exist_ok=True)
        with open(os.path.join(AGY_DIR, "GEMINI.md"), "w", encoding="utf-8") as f:
            f.write(SYSTEM + AGY_RULES)
        now = time.time()
        for name in os.listdir(AGY_DIR):
            path = os.path.join(AGY_DIR, name)
            if name.startswith("sel-") and now - os.path.getmtime(path) > 1800:
                os.remove(path)
        prune_agy()
        self.n = 0
        self.stderr = []
        try:
            self.proc = subprocess.Popen(
                ["agy", "--input-format", "stream-json", "--output-format", "stream-json",
                 "--model", model, "--print="],
                cwd=AGY_DIR, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        except FileNotFoundError:
            self.proc = None
            return
        # drain stderr so a chatty agy can't block on a full pipe
        threading.Thread(target=lambda: self.stderr.extend(l.strip() for l in self.proc.stderr if l.strip()),
                         daemon=True).start()

    def ask(self, text, image):
        if not self.proc:
            emit("error", "`agy` not found — install antigravity-cli (AUR).")
            emit("done")
            return
        png = image_png(image)
        if png:
            self.n += 1
            name = f"sel-{os.getpid()}-{self.n}.png"
            with open(os.path.join(AGY_DIR, name), "wb") as f:
                f.write(png)
            text = f"[Screen selection: ./{name}]\n\n{text}"
        msg = {"event": "user", "message": {"role": "user", "content": [{"type": "text", "text": text}]}}
        try:
            self.proc.stdin.write(json.dumps(msg) + "\n")
            self.proc.stdin.flush()
        except (BrokenPipeError, ValueError):
            pass   # agy is gone; reported below
        emit("status", "Thinking")
        streamed = False
        for line in self.proc.stdout:
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            kind = ev.get("event")
            if kind == "init" and ev.get("conversation_id"):
                emit("conv", ev["conversation_id"])
                remember_agy(ev["conversation_id"])
            elif kind == "step_update":
                step = ev["step_update"]
                if step.get("step_type") == "tool" and step.get("state") == "ACTIVE":
                    if streamed:
                        emit("reset")
                        streamed = False
                    emit("status", self.STATUS.get(step.get("tool_name"), "Working"))
                elif step.get("step_type") == "agent_response" and step.get("text_delta"):
                    if not streamed and not step["text_delta"].strip():
                        continue
                    streamed = True
                    emit("delta", step["text_delta"])
            elif kind == "result":
                res = ev["result"]
                if res.get("status") != "SUCCESS":
                    emit("error", f"Gemini: {res.get('error') or 'the request failed.'}")
                elif not streamed and res.get("response", "").strip():
                    emit("delta", res["response"])
                elif not streamed:
                    denied = ", ".join(d.get("display_name") or d.get("action", "?") for d in res.get("denied_actions") or [])
                    emit("error", f"Gemini wanted to use {denied or 'a tool'}, which isn't allowed here. "
                                  "Continue in Antigravity to let it." if denied else "Gemini gave no answer.")
                emit("done")
                return
        time.sleep(0.2)   # let the stderr thread catch the last lines
        emit("error", (self.stderr[-1] if self.stderr else "agy exited.") + " Is `agy` signed in? Run `agy` once in a terminal.")
        emit("done")


def remember_agy(conv):
    """Note a conversation this overlay started, so prune_agy() can find it."""
    os.makedirs(STATE, exist_ok=True)
    path = os.path.join(STATE, "agy-conversations.json")
    try:
        seen = json.load(open(path))
    except (OSError, ValueError):
        seen = {}
    seen[conv] = time.time()
    with open(path, "w") as f:
        json.dump(seen, f)


def prune_agy():
    """Delete the overlay's own agy conversations older than AGY_KEEP_DAYS."""
    path = os.path.join(STATE, "agy-conversations.json")
    try:
        seen = json.load(open(path))
    except (OSError, ValueError):
        return
    cutoff = time.time() - AGY_KEEP_DAYS * 86400
    old = [c for c, t in seen.items() if t < cutoff and re.fullmatch(r"[0-9a-f-]{36}", c)]
    for conv in old:
        shutil.rmtree(os.path.join(AGY_HOME, "brain", conv), ignore_errors=True)
        for rel in (f"conversations/{conv}.db", f"annotations/{conv}.pbtxt", f"presence/{conv}.lock"):
            try:
                os.remove(os.path.join(AGY_HOME, rel))
            except OSError:
                pass
        del seen[conv]
    if old:
        with open(path, "w") as f:
            json.dump(seen, f)


class Claude:
    """Claude Code CLI on the user's subscription; one long-lived session."""

    def __init__(self, model):
        self.proc = subprocess.Popen(
            ["claude", "-p", "--input-format", "stream-json", "--output-format", "stream-json",
             "--verbose", "--include-partial-messages", "--no-session-persistence",
             "--model", model, "--tools", "WebSearch,WebFetch", "--allowedTools", "WebSearch,WebFetch",
             "--append-system-prompt", SYSTEM],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def ask(self, text, image):
        content = []
        png = image_png(image)
        if png:
            content.append({"type": "image", "source": {"type": "base64", "media_type": "image/png",
                                                        "data": base64.b64encode(png).decode()}})
        content.append({"type": "text", "text": text})
        self.proc.stdin.write(json.dumps({"type": "user", "message": {"role": "user", "content": content}}) + "\n")
        self.proc.stdin.flush()
        streamed = False
        for line in self.proc.stdout:
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            if ev.get("type") == "stream_event":
                e = ev["event"]
                if e.get("type") == "content_block_start":
                    b = e["content_block"]
                    if b.get("type") == "tool_use":
                        emit("reset")
                        streamed = False
                        emit("status", "Reading" if b.get("name") == "WebFetch" else "Searching the web")
                    elif b.get("type") == "text" and streamed:
                        emit("delta", "\n\n")
                elif e.get("type") == "content_block_delta" and e["delta"].get("type") == "text_delta":
                    streamed = True
                    emit("delta", e["delta"]["text"])
            elif ev.get("type") == "result":
                if ev.get("is_error"):
                    emit("error", ev.get("result") or "Claude returned an error.")
                elif not streamed and ev.get("result"):
                    emit("delta", ev["result"])
                emit("done")
                return
        err = self.proc.stderr.read().strip().splitlines()
        emit("error", (err[-1] if err else "Claude exited.") + " Is `claude` logged in?")
        emit("done")


class Gemini:
    """Gemini API (free key from aistudio.google.com).

    Google Search grounding has no free-tier quota (429), so web access uses the
    same DuckDuckGo tools as the local model, via ordinary function calling."""

    DECLS = [{"functionDeclarations": [t["function"] for t in TOOLS]}]

    def __init__(self, model):
        self.model = model
        self.history = []

    def ask(self, text, image):
        try:
            key = open(GEMINI_KEY_FILE).read().strip()
        except OSError:
            emit("error", f"No Gemini API key. Create one at https://aistudio.google.com/apikey "
                          f"and save it to `{GEMINI_KEY_FILE}`.")
            emit("done")
            return
        parts = []
        png = image_png(image)
        if png:
            parts.append({"inline_data": {"mime_type": "image/png", "data": base64.b64encode(png).decode()}})
        parts.append({"text": text})
        mark = len(self.history)
        self.history.append({"role": "user", "parts": parts})
        try:
            rounds = 3   # each round is a request against the per-minute quota
            for n in range(rounds):
                # last round: no tools, so it has to answer with what it found
                model_parts = self._round(key, tools=n < rounds - 1)
                # Sent back verbatim: Gemini 3 needs its thoughtSignature fields.
                self.history.append({"role": "model", "parts": model_parts})
                calls = [p["functionCall"] for p in model_parts if "functionCall" in p]
                if not calls:
                    break
                emit("reset")
                self.history.append({"role": "user", "parts": [
                    {"functionResponse": {**({"id": c["id"]} if c.get("id") else {}), "name": c["name"],
                                          "response": {"content": run_tool(c["name"], c.get("args") or {})}}}
                    for c in calls]})
                emit("status", "Thinking")
            else:
                # still asking for tools after the last round: make it answer
                self.history.append({"role": "user", "parts": [
                    {"text": "Answer now from the results above. Do not search again."}]})
                self.history.append({"role": "model", "parts": self._round(key, tools=False)})
        except urllib.error.HTTPError as e:
            del self.history[mark:]
            msg = http_error(e)
            if e.code == 429:
                per = "day" if getattr(self, "daily", False) else "minute"
                lim = getattr(self, "limit", None)
                msg = (f"Free-tier limit reached{f' ({lim} requests a {per})' if lim else ''}. "
                       f"Switch model, or try again {'tomorrow' if per == 'day' else 'in a minute'}.")
            emit("error", f"Gemini: {msg}")
        except Exception as e:
            del self.history[mark:]
            emit("error", f"Gemini: {e}")
        emit("done")

    def _flat(self):
        """History with tool calls/results as plain text. Some models (Flash-Lite)
        keep calling tools even with functionCallingConfig NONE; with no tool
        parts left to imitate and no tools declared, they answer."""
        out = []
        for turn in self.history:
            parts = []
            for p in turn["parts"]:
                if "functionCall" in p:
                    continue
                if "functionResponse" in p:
                    parts.append({"text": "Web results (context for your answer):\n"
                                          + p["functionResponse"]["response"]["content"]})
                elif (p.get("text") or "").strip() or "inline_data" in p:
                    parts.append({k: v for k, v in p.items() if k != "thoughtSignature"})
            if parts:
                if out and out[-1]["role"] == turn["role"]:
                    out[-1]["parts"] += parts
                else:
                    out.append({"role": turn["role"], "parts": parts})
        return out

    def _round(self, key, tools=True):
        # The free tier rate-limits per minute; wait out short limits once.
        for attempt in range(2):
            try:
                return self._stream(key, tools)
            except urllib.error.HTTPError as e:
                if e.code != 429 or attempt:
                    raise
                body = e.read().decode("utf-8", "replace")
                m = re.search(r'"retryDelay":\s*"(\d+(?:\.\d+)?)s"', body) or re.search(r"retry in (\d+(?:\.\d+)?)s", body)
                wait = float(m.group(1)) if m else 99
                q = re.search(r'"quotaValue":\s*"(\d+)"', body)
                self.limit = q.group(1) if q else None
                if wait > 40 or "PerDay" in body:
                    self.daily = "PerDay" in body
                    raise urllib.error.HTTPError(e.url, e.code, e.msg, e.hdrs, None)
                emit("status", f"Rate-limited, retrying in {round(wait)}s")
                time.sleep(wait + 0.5)
                emit("status", "Thinking")

    def _stream(self, key, tools):
        body = {"contents": self.history if tools else self._flat(),
                "systemInstruction": {"parts": [{"text": SYSTEM}]}}
        if tools:
            body["tools"] = self.DECLS
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:streamGenerateContent?alt=sse"
        out = []
        with http_json(url, body, {"x-goog-api-key": key}, timeout=120) as r:
            for raw in r:
                line = raw.decode().strip()
                if not line.startswith("data:"):
                    continue
                cand = (json.loads(line[5:]).get("candidates") or [{}])[0]
                for p in cand.get("content", {}).get("parts", []):
                    if "functionCall" in p or "text" not in p or p.get("thought"):
                        out.append(p)
                        continue
                    emit("delta", p["text"])
                    if out and "text" in out[-1] and not out[-1].get("thought") and "functionCall" not in out[-1]:
                        out[-1]["text"] += p["text"]
                        if p.get("thoughtSignature"):
                            out[-1]["thoughtSignature"] = p["thoughtSignature"]
                    else:
                        out.append(dict(p))
        return out


class Local:
    """Ollama on this machine, with keyless web search via DuckDuckGo."""

    def __init__(self, model):
        self.model = model
        self.messages = [{"role": "system", "content": SYSTEM}]

    def ask(self, text, image):
        msg = {"role": "user", "content": text}
        png = image_png(image)
        if png:
            msg["images"] = [base64.b64encode(png).decode()]
        self.messages.append(msg)
        emit("status", "Thinking")
        try:
            rounds = 4
            for n in range(rounds):
                calls, content = self._round(tools=n < rounds - 1)
                self.messages.append({"role": "assistant", "content": content,
                                      **({"tool_calls": calls} if calls else {})})
                if not calls:
                    break
                emit("reset")
                for c in calls:
                    f = c["function"]
                    args = f.get("arguments") or {}
                    if isinstance(args, str):
                        args = json.loads(args or "{}")
                    self.messages.append({"role": "tool", "tool_name": f["name"],
                                          "content": run_tool(f["name"], args)})
                emit("status", "Thinking")
        except urllib.error.URLError as e:
            self.messages.pop()
            reason = getattr(e, "reason", e)
            if isinstance(e, urllib.error.HTTPError):
                reason = http_error(e)
            emit("error", f"Local model unavailable ({reason}). Is ollama running "
                          f"(`systemctl start ollama`) and `{self.model}` pulled?")
        emit("done")

    def _round(self, tools=True):
        body = {"model": self.model, "messages": self.messages, "tools": TOOLS if tools else [], "stream": True,
                "think": False, "keep_alive": LOCAL_KEEP, "options": LOCAL_OPTS}
        calls, content = [], ""
        with http_json(f"{OLLAMA}/api/chat", body, timeout=300) as r:
            for raw in r:
                chunk = json.loads(raw)
                if chunk.get("error"):
                    raise urllib.error.URLError(chunk["error"])
                m = chunk.get("message", {})
                if m.get("content"):
                    content += m["content"]
                    emit("delta", m["content"])
                calls += m.get("tool_calls") or []
        return calls, content


def check():
    gemini = os.path.isfile(GEMINI_KEY_FILE)
    try:
        with http_json(f"{OLLAMA}/api/tags", timeout=1.5) as r:
            pulled = [m["name"] for m in json.load(r).get("models", [])]
        local = {"ok": True, "models": pulled}
    except Exception:
        local = {"ok": False, "models": []}
    print(json.dumps({
        "antigravity": {"ok": shutil.which("agy") is not None},
        "claude": {"ok": shutil.which("claude") is not None},
        "gemini": {"ok": gemini},
        "local": local,
    }))


def warm(model):
    """An empty /api/generate loads the model without generating anything."""
    try:
        http_json(f"{OLLAMA}/api/generate", {"model": model, "keep_alive": LOCAL_KEEP, "options": LOCAL_OPTS}, timeout=120).read()
    except Exception:
        pass


def main():
    if sys.argv[1:2] == ["check"]:
        return check()
    if sys.argv[1:2] == ["warm"]:
        return warm(sys.argv[2])
    provider, model = sys.argv[1], sys.argv[2]
    engine = {"antigravity": Antigravity, "claude": Claude, "gemini": Gemini, "local": Local}[provider](model)
    for line in sys.stdin:
        if not line.strip():
            continue
        req = json.loads(line)
        engine.ask(req.get("text", ""), req.get("image"))


if __name__ == "__main__":
    main()
