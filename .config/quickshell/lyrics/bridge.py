#!/usr/bin/env python3
"""Finds lyrics for the game overlay. shell.qml runs this and talks over pipes.

stdin:  {"id", "title", "artist", "album", "length"}   the track MPRIS reports
stdout: {"id", "source", "lines": [[seconds, text], ...]}

Spotify's own lyrics need the client's login, so they can't be fetched from
here: ~/.config/spicetify/Extensions/lyrics-bridge.js POSTs them to this port
on every song change. LRCLIB (free, no key) covers songs Spotify has none for,
and everything until Spotify has been restarted with the extension.
"""
import json
import os
import re
import sys
import threading
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 48721
ORIGIN = 'https://xpui.app.spotify.com'     # every other web page gets a 403
LRCLIB = 'https://lrclib.net/api'
AGENT = 'quickshell-lyrics-overlay'
CACHE = os.path.join(os.environ.get('XDG_RUNTIME_DIR') or '/tmp', 'quickshell-lyrics-cache.json')

lock = threading.Lock()
current = {}        # the track shell.qml is showing
try:
    with open(CACHE) as _f:
        spotify = json.load(_f)     # track id -> lines, survives `qs -c lyrics` restarts
except (OSError, ValueError):
    spotify = {}


def emit(track_id, source, lines):
    print(json.dumps({'id': track_id, 'source': source, 'lines': lines}), flush=True)


def lrc_lines(lrc):
    lines = []
    for raw in lrc.splitlines():
        stamps = re.findall(r'\[(\d+):(\d+(?:\.\d+)?)\]', raw)
        text = re.sub(r'\[[^\]]*\]', '', raw).strip()
        lines += [[int(m) * 60 + float(s), text] for m, s in stamps]
    return sorted(lines, key=lambda l: l[0])


def lrclib_get(path, **query):
    url = f'{LRCLIB}/{path}?{urllib.parse.urlencode(query)}'
    request = urllib.request.Request(url, headers={'User-Agent': AGENT})
    try:
        with urllib.request.urlopen(request, timeout=8) as reply:
            return json.load(reply)
    except (OSError, ValueError):       # 404 = not found, also an OSError
        return None


def lrclib(track):
    title, artist = track.get('title', ''), track.get('artist', '')
    length = track.get('length') or 0
    best = lrclib_get('get', track_name=title, artist_name=artist,
                      album_name=track.get('album', ''), duration=round(length))
    if not (best and best.get('syncedLyrics')):
        hits = lrclib_get('search', track_name=title, artist_name=artist) or []
        hits = [h for h in hits if h.get('syncedLyrics')
                and (not length or abs((h.get('duration') or 0) - length) <= 3)]
        best = hits[0] if hits else None
    return lrc_lines(best['syncedLyrics']) if best else []


def look_up(track):
    lines = lrclib(track)
    with lock:
        if lines and current.get('id') == track['id'] and not spotify.get(track['id']):
            emit(track['id'], 'lrclib', lines)


def read_tracks():
    for raw in sys.stdin:
        try:
            track = json.loads(raw)
        except ValueError:
            continue
        with lock:
            current.clear()
            current.update(track)
            known = spotify.get(track.get('id'))
            if known:
                emit(track['id'], 'spotify', known)
        if track.get('id') and not known:
            threading.Thread(target=look_up, args=(track,), daemon=True).start()


class Handler(BaseHTTPRequestHandler):
    def cors(self):
        self.send_header('Access-Control-Allow-Origin', ORIGIN)
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.send_header('Access-Control-Allow-Private-Network', 'true')
        self.send_header('Content-Length', '0')

    def do_OPTIONS(self):
        ok = self.headers.get('Origin') == ORIGIN
        self.send_response(204 if ok else 403)
        self.cors()
        self.end_headers()

    def do_POST(self):
        size = int(self.headers.get('Content-Length') or 0)
        if self.headers.get('Origin') != ORIGIN or self.path != '/lyrics' or size > 1 << 20:
            self.send_response(403)
            self.end_headers()
            return
        body = self.rfile.read(size)
        self.send_response(204)
        self.cors()
        self.end_headers()
        try:
            data = json.loads(body)
            track_id, lines = data['id'], [[float(t), str(s)] for t, s in data['lines']]
        except (ValueError, KeyError, TypeError):
            return
        with lock:
            if len(spotify) > 200:
                spotify.clear()
            spotify[track_id] = lines
            try:
                fd = os.open(CACHE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                with os.fdopen(fd, 'w') as f:
                    json.dump(spotify, f)
            except OSError:
                pass
            if lines and current.get('id') == track_id:
                emit(track_id, 'spotify', lines)

    def log_message(self, *args):
        pass


if __name__ == '__main__':
    server = ThreadingHTTPServer(('127.0.0.1', PORT), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    read_tracks()       # returns when the overlay goes away and stdin closes
