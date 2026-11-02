"""데이터 추출 문서 생성기 (PDF · Excel · CSV).

현업 MES/QMS 추출 표준(IATF 16949 추적성 · 데이터 무결성)에 맞춘 4단 구조:
  1) 문서 통제 헤더  : 문서명, 출력 시스템, 출력자(성명/ID), 출력 일시, 보안 등급, (PDF) 결재란
  2) 조회 조건 블록  : 화면에서 선택한 조건을 그대로 기록 → 나중에 파일만 봐도 어떤 조건의 데이터인지 알 수 있음
  3) KPI 요약 · 차트 : 건수/비율/통계 요약 + 화면 차트(흰 배경 · 2배 해상도로 다시 그린 이미지)
  4) 상세 데이터 표  : No 부터 시작. 단위는 컬럼 헤더에만(예: '측정값 (kA)'), 셀에는 순수 숫자

포맷별 규칙
  · CSV  : 서식·메타데이터 없이 1행 헤더 + 데이터. UTF-8 with BOM. 일시 'YYYY-MM-DD HH:mm:ss.SSS'
  · Excel: 시트 분리(요약 / 상세). 상세 시트는 셀 병합 없음, 1행 틀 고정, 자동 필터, NG 셀 연한 빨강(조건부 서식)
  · PDF  : A4 가로. 표 머리글 페이지마다 반복, 'Page X of Y', 보안 워터마크, 출력자·일시 각인
"""
from __future__ import annotations

import csv
import io
import os
from dataclasses import dataclass, field
from datetime import datetime

from backend.config import EXPORT_PDF_ROW_LIMIT, EXPORT_SECURITY_LABEL, EXPORT_SYSTEM_NAME

TS_FMT = "%Y-%m-%d %H:%M:%S"


# ───────────────────────────── 문서 모델 ─────────────────────────────
@dataclass
class Col:
    title: str
    unit: str | None = None     # 헤더에만 표기: '측정값 (kA)'
    kind: str = "text"          # text | num | int | datetime | verdict
    dec: int | None = None      # num 소수 자릿수 (Excel 표시 형식)
    width: int = 14             # Excel 열 너비(문자 수)

    @property
    def header(self) -> str:
        return f"{self.title} ({self.unit})" if self.unit else self.title


@dataclass
class Table:
    name: str                   # 시트 이름 / PDF 소제목
    columns: list[Col]
    rows: list[list]
    note: str | None = None


@dataclass
class Report:
    title: str                  # 예: '[HW01] 용접 센서 트렌드 분석 리포트'
    file_stem: str              # 예: '용접현황_센서트렌드_20261014'
    filters: list[tuple[str, str]]
    kpis: list[tuple[str, str]] = field(default_factory=list)
    summary: Table | None = None
    charts: list[tuple[str, bytes]] = field(default_factory=list)   # (제목, PNG)
    details: list[Table] = field(default_factory=list)              # 첫 번째 표 = CSV 대상(주 데이터)


@dataclass
class Meta:
    user_name: str
    login_id: str
    printed_at: datetime

    @property
    def printed(self) -> str:
        return self.printed_at.strftime(TS_FMT)

    @property
    def control(self) -> list[tuple[str, str]]:
        return [("출력 시스템", EXPORT_SYSTEM_NAME), ("출력자", f"{self.user_name} ({self.login_id})"),
                ("출력 일시", self.printed), ("보안 등급", EXPORT_SECURITY_LABEL)]


def total_rows(rep: Report) -> int:
    return sum(len(t.rows) for t in rep.details)


def _ts(v) -> str:
    """DB 일시 'YYYY-MM-DD HH:MM:SS' → 표준 'YYYY-MM-DD HH:mm:ss.SSS'"""
    if not v:
        return ""
    s = str(v)
    return s if "." in s else f"{s}.000"


def _to_dt(v):
    try:
        return datetime.strptime(str(v)[:19], TS_FMT) if v else None
    except ValueError:
        return None


# ───────────────────────────── CSV ─────────────────────────────
def write_csv(rep: Report) -> bytes:
    t = rep.details[0]
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\r\n")
    w.writerow([c.header for c in t.columns])
    for r in t.rows:
        w.writerow(["" if v is None else (_ts(v) if c.kind == "datetime" else v) for c, v in zip(t.columns, r)])
    return ("\ufeff" + buf.getvalue()).encode("utf-8")   # UTF-8 with BOM (엑셀 한글 깨짐 방지)


# ───────────────────────────── Excel ─────────────────────────────
def write_xlsx(rep: Report, meta: Meta) -> bytes:
    from openpyxl import Workbook
    from openpyxl.drawing.image import Image as XLImage
    from openpyxl.formatting.rule import FormulaRule
    from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
    from openpyxl.utils import get_column_letter

    bold, title_font = Font(bold=True), Font(bold=True, size=15)
    head_fill = PatternFill("solid", fgColor="E8ECF2")
    label_fill = PatternFill("solid", fgColor="F4F6F8")
    ng_fill = PatternFill("solid", fgColor="FDE2E2")
    thin = Side(style="thin", color="C9CFD8")
    box = Border(left=thin, right=thin, top=thin, bottom=thin)

    wb = Workbook()
    ws = wb.active
    ws.title = "요약"
    ws.sheet_view.showGridLines = False
    ws.column_dimensions["A"].width = 18
    for col in "BCDEFGHIJKL":
        ws.column_dimensions[col].width = 14

    r = 1
    ws.cell(r, 1, rep.title).font = title_font
    r += 2

    def kv_block(title, items):
        nonlocal r
        ws.cell(r, 1, title).font = bold
        r += 1
        for k, v in items:
            a, b = ws.cell(r, 1, k), ws.cell(r, 2, v)
            a.fill, a.font, a.border, b.border = label_fill, bold, box, box
            r += 1
        r += 1

    kv_block("문서 정보", meta.control)
    kv_block("조회 조건", rep.filters)
    if rep.kpis:
        kv_block("핵심 지표", rep.kpis)

    if rep.summary:   # 요약 표 (병합 없이)
        t = rep.summary
        ws.cell(r, 1, t.name).font = bold
        r += 1
        for j, c in enumerate(t.columns, 1):
            cell = ws.cell(r, j, c.header)
            cell.font, cell.fill, cell.border = bold, head_fill, box
            cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        for row in t.rows:
            r += 1
            for j, (c, v) in enumerate(zip(t.columns, row), 1):
                cell = ws.cell(r, j, v)
                cell.border = box
                if c.kind == "num" and c.dec is not None:
                    cell.number_format = "0" if c.dec == 0 else "0." + "0" * c.dec
                if c.kind == "verdict" and v == "NG":
                    cell.fill = ng_fill
        r += 2

    for title, png in rep.charts:   # 차트 이미지 (화면 차트를 흰 배경 · 2배 해상도로 다시 그린 것)
        ws.cell(r, 1, title).font = bold
        r += 1
        img = XLImage(io.BytesIO(png))
        ratio = 900 / img.width
        img.width, img.height = int(img.width * ratio), int(img.height * ratio)
        ws.add_image(img, f"A{r}")
        r += int(img.height / 20) + 2

    for t in rep.details:   # 상세(Raw) 시트: 병합 금지 · 1행 고정 · 자동 필터 · NG 조건부 서식
        ds = wb.create_sheet(t.name[:31])
        ds.append([c.header for c in t.columns])
        for j, c in enumerate(t.columns, 1):
            h = ds.cell(1, j)
            h.font, h.fill, h.border = bold, head_fill, box
            h.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
            ds.column_dimensions[get_column_letter(j)].width = c.width
        for row in t.rows:
            ds.append([_to_dt(v) if c.kind == "datetime" else v for c, v in zip(t.columns, row)])
        n = len(t.rows) + 1
        for j, c in enumerate(t.columns, 1):
            L = get_column_letter(j)
            if c.kind == "datetime":
                for (cell,) in ds.iter_rows(min_row=2, max_row=n, min_col=j, max_col=j):
                    cell.number_format = "yyyy-mm-dd hh:mm:ss.000"
            elif c.kind == "num" and c.dec is not None:
                fmt = "0" if c.dec == 0 else "0." + "0" * c.dec
                for (cell,) in ds.iter_rows(min_row=2, max_row=n, min_col=j, max_col=j):
                    cell.number_format = fmt
            elif c.kind == "verdict" and n > 1:
                ds.conditional_formatting.add(f"{L}2:{L}{n}", FormulaRule(formula=[f'${L}2="NG"'], fill=ng_fill))
        ds.freeze_panes = "A2"
        ds.auto_filter.ref = f"A1:{get_column_letter(len(t.columns))}{n}"

    out = io.BytesIO()
    wb.save(out)
    return out.getvalue()


# ───────────────────────────── PDF ─────────────────────────────
_FONT: tuple[str, str] | None = None


def _pdf_font() -> tuple[str, str]:
    """한글 폰트 등록. 우선순위: 환경변수 QMS_PDF_FONT → backend/fonts → Windows 맑은 고딕 → 리눅스 나눔고딕 → 내장 CID 글꼴."""
    global _FONT
    if _FONT:
        return _FONT
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont

    here = os.path.join(os.path.dirname(__file__), "fonts")
    pairs = [
        (os.getenv("QMS_PDF_FONT", ""), os.getenv("QMS_PDF_FONT_BOLD", "")),
        (os.path.join(here, "NanumGothic.ttf"), os.path.join(here, "NanumGothicBold.ttf")),
        (r"C:\Windows\Fonts\malgun.ttf", r"C:\Windows\Fonts\malgunbd.ttf"),
        ("/usr/share/fonts/truetype/nanum/NanumGothic.ttf", "/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf"),
        ("/tmp/fonts/NanumGothic.ttf", "/tmp/fonts/NanumGothicBold.ttf"),
    ]
    for reg, bld in pairs:
        if reg and os.path.exists(reg):
            pdfmetrics.registerFont(TTFont("KR", reg))
            pdfmetrics.registerFont(TTFont("KR-B", bld if bld and os.path.exists(bld) else reg))
            _FONT = ("KR", "KR-B")
            return _FONT
    from reportlab.pdfbase.cidfonts import UnicodeCIDFont
    pdfmetrics.registerFont(UnicodeCIDFont("HYGothic-Medium"))
    _FONT = ("HYGothic-Medium", "HYGothic-Medium")
    return _FONT


def write_pdf(rep: Report, meta: Meta) -> bytes:
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4, landscape
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.lib.units import mm
    from reportlab.pdfgen import canvas as pdfcanvas
    from reportlab.platypus import Image, KeepTogether, Paragraph, SimpleDocTemplate, Spacer, Table as PTable, TableStyle

    F, FB = _pdf_font()
    page = landscape(A4)
    W = page[0] - 24 * mm
    st = lambda size=8.5, font=F, color=colors.HexColor("#1e293b"), lead=None: ParagraphStyle(  # noqa: E731
        "s", fontName=font, fontSize=size, leading=lead or size * 1.35, textColor=color)
    p_title, p_h, p_cell, p_note = st(15, FB), st(10, FB), st(7.6), st(7.5, F, colors.HexColor("#64748b"))
    grid = colors.HexColor("#c9cfd8")
    head_bg, label_bg, ng_bg = colors.HexColor("#e8ecf2"), colors.HexColor("#f4f6f8"), colors.HexColor("#fde2e2")
    base_style = [("FONTNAME", (0, 0), (-1, -1), F), ("FONTSIZE", (0, 0), (-1, -1), 7.8),
                  ("GRID", (0, 0), (-1, -1), 0.4, grid), ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                  ("TOPPADDING", (0, 0), (-1, -1), 2.5), ("BOTTOMPADDING", (0, 0), (-1, -1), 2.5)]

    def fmt(c: Col, v):
        if v is None or v == "":
            return ""
        if c.kind == "datetime":
            return str(v)[:19]
        if c.kind == "num" and isinstance(v, (int, float)) and c.dec is not None:
            return f"{v:,.{c.dec}f}"
        if c.kind == "int" and isinstance(v, (int, float)):
            return f"{int(v):,}"
        return str(v)

    def kv_table(items, cols=2):
        cells = []
        for i in range(0, len(items), cols):
            row = []
            for k, v in items[i:i + cols]:
                row += [k, Paragraph(str(v), p_cell)]
            row += ["", ""] * (cols - len(items[i:i + cols]))
            cells.append(row)
        widths = [28 * mm, W / cols - 28 * mm] * cols
        t = PTable(cells, colWidths=widths)
        t.setStyle(TableStyle(base_style + [("FONTNAME", (0, 0), (-1, -1), F)]
                              + [("BACKGROUND", (j, 0), (j, -1), label_bg) for j in range(0, cols * 2, 2)]
                              + [("FONTNAME", (j, 0), (j, -1), FB) for j in range(0, cols * 2, 2)]))
        return t

    def data_table(t: Table, limit: int | None = None):
        rows = t.rows if limit is None else t.rows[:limit]
        body = [[Paragraph(c.header, st(7.4, FB)) for c in t.columns]] + [[fmt(c, v) for c, v in zip(t.columns, r)] for r in rows]
        total_w = sum(c.width for c in t.columns)
        pt = PTable(body, colWidths=[W * c.width / total_w for c in t.columns], repeatRows=1)   # 머리글 페이지마다 반복
        sty = base_style + [("BACKGROUND", (0, 0), (-1, 0), head_bg), ("ALIGN", (0, 0), (-1, 0), "CENTER")]
        for j, c in enumerate(t.columns):
            if c.kind in ("num", "int"):
                sty.append(("ALIGN", (j, 1), (j, -1), "RIGHT"))
            if c.kind == "verdict":
                sty.append(("ALIGN", (j, 1), (j, -1), "CENTER"))
                sty += [("BACKGROUND", (j, i), (j, i), ng_bg) for i, r in enumerate(rows, 1) if r[j] == "NG"]
                sty += [("TEXTCOLOR", (j, i), (j, i), colors.HexColor("#b91c1c")) for i, r in enumerate(rows, 1) if r[j] == "NG"]
        pt.setStyle(TableStyle(sty))
        return pt

    # ── 본문
    approval = PTable([["담당", "검토", "승인"], ["", "", ""]], colWidths=[18 * mm] * 3, rowHeights=[5.5 * mm, 13 * mm])
    approval.setStyle(TableStyle(base_style + [("ALIGN", (0, 0), (-1, -1), "CENTER"), ("BACKGROUND", (0, 0), (-1, 0), label_bg)]))
    head = PTable([[Paragraph(rep.title, p_title), approval]], colWidths=[W - 56 * mm, 56 * mm])
    head.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "MIDDLE"), ("LEFTPADDING", (0, 0), (-1, -1), 0)]))
    story = [head, Spacer(1, 4 * mm), kv_table(meta.control, 4), Spacer(1, 4 * mm),
             Paragraph("조회 조건", p_h), Spacer(1, 1.5 * mm), kv_table(rep.filters, 3), Spacer(1, 4 * mm)]
    if rep.kpis:
        story += [Paragraph("핵심 지표", p_h), Spacer(1, 1.5 * mm), kv_table(rep.kpis, 4), Spacer(1, 4 * mm)]
    if rep.summary:
        story += [Paragraph(rep.summary.name, p_h), Spacer(1, 1.5 * mm), data_table(rep.summary), Spacer(1, 4 * mm)]
    for title, png in rep.charts:
        img = Image(io.BytesIO(png))
        ratio = min(W / img.imageWidth, 62 * mm / img.imageHeight)
        img.drawWidth, img.drawHeight = img.imageWidth * ratio, img.imageHeight * ratio
        story.append(KeepTogether([Paragraph(title, p_h), Spacer(1, 1 * mm), img, Spacer(1, 3 * mm)]))
    for t in rep.details:
        lim = EXPORT_PDF_ROW_LIMIT if len(t.rows) > EXPORT_PDF_ROW_LIMIT else None
        story += [Paragraph(f"{t.name} ({len(t.rows):,}건)", p_h), Spacer(1, 1.5 * mm)]
        if t.note:
            story += [Paragraph(t.note, p_note), Spacer(1, 1 * mm)]
        if lim:
            story += [Paragraph(f"※ PDF에는 앞 {lim:,}건만 수록했습니다. 전체 {len(t.rows):,}건은 Excel 또는 CSV로 추출하세요.", p_note), Spacer(1, 1 * mm)]
        story += [data_table(t, lim) if t.rows else Paragraph("데이터가 없습니다.", p_note), Spacer(1, 5 * mm)]

    # ── 쪽 번호(Page X of Y) · 워터마크 · 출력자 각인: 2단계 렌더링
    class NumberedCanvas(pdfcanvas.Canvas):
        def __init__(self, *a, **k):
            super().__init__(*a, **k)
            self._pages = []

        def showPage(self):
            self._pages.append(dict(self.__dict__))
            self._startPage()

        def save(self):
            n = len(self._pages)
            for s in self._pages:
                self.__dict__.update(s)
                self._decorate(n)
                super().showPage()
            super().save()

        def _decorate(self, n):
            w, h = page
            self.saveState()
            self.setFont(FB, 46)
            self.setFillColor(colors.Color(0.55, 0.6, 0.68, alpha=0.08))
            self.translate(w / 2, h / 2)
            self.rotate(28)
            self.drawCentredString(0, 0, f"{EXPORT_SECURITY_LABEL} · {EXPORT_SYSTEM_NAME}")
            self.restoreState()
            self.setFont(F, 7.5)
            self.setFillColor(colors.HexColor("#64748b"))
            self.drawString(12 * mm, 7 * mm, f"{EXPORT_SYSTEM_NAME} · 출력자 {meta.user_name}({meta.login_id}) · {meta.printed} · {EXPORT_SECURITY_LABEL}")
            self.drawRightString(w - 12 * mm, 7 * mm, f"Page {self._pageNumber} of {n}")

    out = io.BytesIO()
    doc = SimpleDocTemplate(out, pagesize=page, leftMargin=12 * mm, rightMargin=12 * mm, topMargin=11 * mm, bottomMargin=13 * mm,
                            title=rep.title, author=f"{meta.user_name}({meta.login_id})", creator=EXPORT_SYSTEM_NAME)
    doc.build(story, canvasmaker=NumberedCanvas)
    return out.getvalue()
