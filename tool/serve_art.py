#!/usr/bin/env python3
"""Serve the repository's character review tool, without a game/web build.

    python3 tool/serve_art.py --port 8000

Development only; the default page reviews the real shipped hero asset.
"""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path, PurePosixPath
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]


class ArtHandler(SimpleHTTPRequestHandler):
    def send_head(self):
        path = unquote(urlsplit(self.path).path)
        if path == '/':
            self.send_response(302)
            self.send_header('Location', '/tool/hero_preview.html')
            self.end_headers()
            return None
        parts = PurePosixPath(path).parts[1:]
        # Review assets only: never expose .git, tool caches, credentials or saves.
        if not parts or parts[0] not in ('tool', 'assets', 'data') or any(p.startswith('.') for p in parts):
            self.send_error(404)
            return None
        return super().send_head()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8000)
    args = parser.parse_args()
    server = ThreadingHTTPServer(('0.0.0.0', args.port), partial(ArtHandler, directory=str(ROOT)))
    print(f'Character review listening on port {args.port}', flush=True)
    server.serve_forever()
