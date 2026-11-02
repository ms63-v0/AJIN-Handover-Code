"""UI 개발 서버: frontend 폴더를 5173 포트로 제공. 브라우저 캐시를 끄는 헤더를 붙여서 수정한 화면이 항상 바로 반영된다.

실행 (로컬 Windows, 기존과 동일):  py serve_ui.py   →  http://127.0.0.1:5173

Codespaces 실행 (선택): 환경변수 UI_API_PROXY 를 주면 /api 와 /health 요청을 그 주소의 백엔드로 넘겨준다.
  UI_API_PROXY=http://127.0.0.1:8000 python3 serve_ui.py
  브라우저는 5173 주소 하나만 보므로 CORS·쿠키 문제가 없다. 환경변수를 주지 않으면 이 기능은 꺼져 있다.
"""
import http.client
import os
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

PROXY = os.getenv("UI_API_PROXY", "").strip().rstrip("/")
HOP_BY_HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailers", "transfer-encoding", "upgrade"}


class NoCacheHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def _is_api(self) -> bool:
        return bool(PROXY) and (self.path.startswith("/api/") or self.path.split("?")[0] == "/health")

    def _proxy(self):
        target = urlsplit(PROXY)
        https = target.scheme == "https"
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        headers = {k: v for k, v in self.headers.items()
                   if k.lower() not in HOP_BY_HOP and k.lower() not in ("host", "content-length", "accept-encoding")}
        if body is not None:
            headers["Content-Length"] = str(len(body))
        port = target.port or (443 if https else 80)
        conn = (http.client.HTTPSConnection if https else http.client.HTTPConnection)(target.hostname, port, timeout=60)
        try:
            conn.request(self.command, self.path, body=body, headers=headers)
            resp = conn.getresponse()
            data = resp.read()
            self.send_response(resp.status, resp.reason)
            for k, v in resp.getheaders():   # Set-Cookie 등 여러 개인 헤더도 모두 그대로 전달
                if k.lower() in HOP_BY_HOP or k.lower() == "content-length":
                    continue
                self.send_header(k, v)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(data)
        except Exception as e:  # noqa: BLE001
            # HTTP 상태 줄은 영문만 가능하므로 한글 설명은 본문(UTF-8)에 넣는다
            msg = f'{{"detail":"백엔드({PROXY})에 연결할 수 없습니다: {type(e).__name__}"}}'.encode("utf-8")
            self.send_response(502, "Bad Gateway")
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(msg)
        finally:
            conn.close()

    def do_GET(self):
        return self._proxy() if self._is_api() else super().do_GET()

    def do_HEAD(self):
        return self._proxy() if self._is_api() else super().do_HEAD()

    def do_POST(self):
        return self._proxy() if self._is_api() else self.send_error(405)

    def do_PUT(self):
        return self._proxy() if self._is_api() else self.send_error(405)

    def do_PATCH(self):
        return self._proxy() if self._is_api() else self.send_error(405)

    def do_DELETE(self):
        return self._proxy() if self._is_api() else self.send_error(405)


if __name__ == "__main__":
    handler = partial(NoCacheHandler, directory=str(Path(__file__).parent / "frontend"))
    if PROXY:
        print(f"UI 서버: http://127.0.0.1:5173  (/api → {PROXY} 로 전달)  (종료: Ctrl+C)")
    else:
        print("UI 서버: http://127.0.0.1:5173  (종료: Ctrl+C)")
    ThreadingHTTPServer(("127.0.0.1", 5173), handler).serve_forever()