"""데모용 비전 오버레이 이미지 생성(SVG). 실제 운영에서는 파일서버의 이미지를 읽어 전달하면 된다."""
import random


def overlay_svg(result: str | None, seed: int, label: str = "") -> str:
    rnd = random.Random(seed)
    ok = result == "OK"
    color = "#1fa045" if ok else "#d62b2b"
    lines = "".join(f'<path d="M0 {rnd.randint(8, 190)} Q80 {rnd.randint(0, 200)} 320 {rnd.randint(8, 190)}" stroke="#ffffff" stroke-opacity="0.05" stroke-width="{rnd.randint(1, 3)}" fill="none"/>' for _ in range(14))
    dx, dy = rnd.randint(-10, 10), rnd.randint(-8, 8)
    box = (f'<rect x="{110 + dx}" y="{56 + dy}" width="100" height="92" fill="none" stroke="{color}" stroke-width="2"/>'
           if ok else f'<rect x="{104 + dx}" y="{50 + dy}" width="112" height="104" fill="{color}" fill-opacity="0.12" stroke="{color}" stroke-width="2.5"/>')
    conf = f"{rnd.uniform(96.5, 99.9):.1f}%" if ok else f"{rnd.uniform(88.0, 97.5):.1f}%"
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 200" width="320" height="200">
<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#7c8084"/><stop offset="1" stop-color="#454a50"/></linearGradient>
<radialGradient id="n" cx="0.4" cy="0.35"><stop offset="0" stop-color="#e4e6e8"/><stop offset="1" stop-color="#8d9298"/></radialGradient></defs>
<rect width="320" height="200" fill="url(#g)"/>{lines}
<circle cx="{160 + dx}" cy="{102 + dy}" r="38" fill="url(#n)" stroke="#2b2f33" stroke-width="2"/>
<circle cx="{160 + dx}" cy="{102 + dy}" r="15" fill="#2b2f33"/><circle cx="{160 + dx}" cy="{102 + dy}" r="23" fill="none" stroke="#c9ccd0" stroke-width="3"/>
{'' if ok else f'<path d="M{128 + dx} {80 + dy} l22 12 m10 6 l24 14" stroke="#3a2a22" stroke-width="3" stroke-linecap="round"/>'}
{box}
<rect x="0" y="0" width="38" height="18" fill="{color}"/><text x="19" y="13" font-family="Arial" font-weight="700" font-size="12" fill="#fff" text-anchor="middle">{'OK' if ok else 'NG'}</text>
<rect x="268" y="0" width="52" height="18" fill="#000" fill-opacity="0.45"/><text x="294" y="13" font-family="Arial" font-weight="700" font-size="11" fill="#fff" text-anchor="middle">{conf}</text>
<text x="8" y="192" font-family="Arial" font-size="9" fill="#fff" fill-opacity="0.7">{label}</text></svg>"""
