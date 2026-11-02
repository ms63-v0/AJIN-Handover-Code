"""백엔드 패키지. import 되는 순간 시간대를 한국 시간(KST)으로 고정한다.

- 어떤 터미널(VS Code, Codespaces)에서 실행해도 datetime.now() 가 같은 시각을 가진다.
- 다른 시간대가 필요하면 환경변수 APP_TZ 로 바꾼다 (기본: Asia/Seoul).
- Windows 는 시스템 시간대를 쓰므로 이 설정이 필요 없다 (이미 KST 이면 그대로).
"""
import os
import time

_tz = os.getenv("APP_TZ", "Asia/Seoul").strip() or "Asia/Seoul"
os.environ["TZ"] = _tz
if hasattr(time, "tzset"):   # Linux/macOS 에서만 존재
    time.tzset()