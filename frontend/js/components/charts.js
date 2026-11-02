/**
 * charts.js — ISA-101(High-Performance HMI) / ASM 가이드라인 기반 트렌드 차트
 *
 *  · 정상은 눈에 띄지 않게, 비정상만 강하게
 *    - 플롯 배경: 연회색(#F4F6F8) / 저채도 다크(#1E232B). 순백·순흑 사용 안 함
 *    - 정상 운전 범위(LCL~UCL)를 옅은 블루 음영 밴드로 표시
 *    - 정상 라인은 차분한 색(네이비·틸·토프), 2px
 *    - 기준 밖으로 나간 선 구간은 즉시 빨간색으로 변환 + 이탈 포인트 표시
 *  · 데이터 결측(수집 중단) 구간은 선을 끊고 '데이터 없음' 음영으로 표시 (이어 그리지 않음)
 *  · 직선 보간만 사용 (곡선 보간 금지)
 *  · 같은 화면 차트끼리 시간축 동기화: 크로스헤어·툴팁·확대/이동 범위 공유
 *  · 확대/이동/마우스 오버 시 자동 스크롤 정지 → [실시간 추종 복귀] 버튼
 *  · 알람 발생 시점 이벤트 마커
 *  · LTTB 다운샘플링 (피크·이상치 보존하며 화면 픽셀 수 이하로 축소)
 */

let DPR = window.devicePixelRatio || 1;
let _export = false;   // 추출용 이미지 생성 중: 테마와 무관하게 흰 배경 라이트 색으로 그린다
const isDark = () => !_export && document.documentElement.dataset.theme === "dark";
const LIGHT_PARTS = { "--part-1": "#1f3a5f", "--part-2": "#2f7f86", "--part-3": "#9a7b5b", "--part-4": "#6b7280", "--part-5": "#7c6aa6" };

function T() {
  const d = isDark();
  return {
    plotBg:    _export ? "#ffffff" : d ? "#1e232b" : "#f4f6f8",   // 인쇄용은 흰 배경(토너 절약)
    gridLine:  d ? "rgba(255,255,255,.06)" : "rgba(30,41,59,.07)",
    frame:     d ? "rgba(255,255,255,.10)" : "rgba(30,41,59,.12)",
    axisLbl:   d ? "#9aa4b2" : "#5b6474",
    normBand:  d ? "rgba(120,160,220,.10)" : "rgba(62,124,177,.09)",   // 정상 운전 범위
    limitLine: d ? "rgba(248,113,113,.75)" : "rgba(200,40,40,.65)",
    limitLbl:  d ? "#f2a3a3" : "#a32020",
    alarm:     d ? "#f87171" : "#d32f2f",                            // 비정상(Critical)
    event:     d ? "rgba(251,146,60,.55)" : "rgba(217,119,6,.55)",   // 알람 이벤트 마커
    eventMark: d ? "#fb923c" : "#d97706",
    gapFill:   d ? "rgba(255,255,255,.035)" : "rgba(30,41,59,.045)",
    gapLbl:    d ? "#6b7280" : "#8a93a3",
    cross:     d ? "rgba(226,232,240,.35)" : "rgba(30,41,59,.30)",
    ring:      d ? "#1e232b" : "#f4f6f8",
    current:   d ? "#fbbf24" : "#b45309",
    okLine:    d ? "#a9c4eb" : "#1f3a5f",
    okBar:     d ? "#4b6a8f" : "#9fb4cc",   // 추이: 생산(OK) 막대 — 차분한 스틸 블루
    rateLine:  d ? "#e2e8f0" : "#1e293b",   // 추이: 불량률 선 — 차콜   // 추이: 정상 생산(차분한 네이비)
    ngLine:    d ? "#f87171" : "#c62828",   // 추이: 불량(비정상 의미의 빨강)
    miniWin:   d ? "rgba(169,196,235,.16)" : "rgba(31,58,95,.10)",
    miniBdr:   d ? "#a9c4eb" : "#1f3a5f",
  };
}

// 'var(--part-1)' 같은 CSS 변수 색을 실제 색으로 (범례 HTML 과 캔버스 색을 하나로 맞추기 위함)
function resolveColor(c) {
  if (!c || !c.startsWith("var(")) return c;
  const name = c.slice(4, -1).trim();
  if (_export && LIGHT_PARTS[name]) return LIGHT_PARTS[name];
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim() || "#5b6474";
}

function makeCanvas(w, h, cursor = "crosshair") {
  const cv = document.createElement("canvas");
  cv.width = Math.round(w * DPR); cv.height = Math.round(h * DPR);
  cv.style.cssText = `width:100%;height:${h}px;display:block;cursor:${cursor}`;
  const ctx = cv.getContext("2d"); ctx.scale(DPR, DPR);
  return { cv, ctx };
}

function niceScale(min, max, steps = 5) {
  if (!(max > min)) { max = min + 1; }
  const raw = (max - min) / steps;
  const mag = Math.pow(10, Math.floor(Math.log10(raw)));
  const step = [1, 2, 2.5, 5, 10].map((f) => f * mag).find((s) => s >= raw);
  const lo = Math.floor(min / step) * step;
  let hi = Math.ceil(max / step) * step;
  if (hi === lo) hi = lo + step;
  return { lo, hi, step };
}
const decimalsFor = (step) => (step >= 10 ? 0 : step >= 1 ? 1 : step >= 0.1 ? 2 : 3);
const hhmm = (t) => new Date(t).toTimeString().slice(0, 5);

/** LTTB 다운샘플링: 형태(피크·골)를 보존하면서 n개 이하로 축소 */
function lttb(pts, n) {
  if (pts.length <= n || n < 3) return pts;
  const out = [pts[0]], every = (pts.length - 2) / (n - 2);
  let a = 0;
  for (let i = 0; i < n - 2; i++) {
    const s = Math.floor((i + 1) * every) + 1, e = Math.min(Math.floor((i + 2) * every) + 1, pts.length);
    let ax = 0, ay = 0;
    for (let j = s; j < e; j++) { ax += pts[j].t; ay += pts[j].v; }
    ax /= (e - s) || 1; ay /= (e - s) || 1;
    const rs = Math.floor(i * every) + 1, re = Math.floor((i + 1) * every) + 1;
    let best = rs, area = -1;
    for (let j = rs; j < re; j++) {
      const ar = Math.abs((pts[a].t - ax) * (pts[j].v - pts[a].v) - (pts[a].t - pts[j].t) * (ay - pts[a].v));
      if (ar > area) { area = ar; best = j; }
    }
    out.push(pts[best]); a = best;
  }
  out.push(pts[pts.length - 1]);
  return out;
}

/** 수집 중단 판정 간격: 평소 간격(중앙값)의 6배 또는 2분 중 큰 값 */
function gapThreshold(times) {
  if (times.length < 3) return Infinity;
  const d = [];
  for (let i = 1; i < times.length; i++) d.push(times[i] - times[i - 1]);
  d.sort((x, y) => x - y);
  return Math.max(d[Math.floor(d.length / 2)] * 6, 120000);
}

function makeTip(container, cls) {
  const el = document.createElement("div");
  el.className = cls; el.hidden = true;
  container.style.position = "relative";
  container.appendChild(el);
  return el;
}

// ══════════════════════════════════════════════════════════════
// trendChart — 대시보드 생산·불량 추이 (MES 표준: 구간별 독립 집계 + 이중 Y축)
//   · 좌측 Y축(주축): 30분 구간별 생산량(EA) — 쌓은 막대(아래 OK + 위 NG = 구간 생산량). 누적하지 않으므로 튄 구간이 바로 보인다
//   · 우측 Y축(보조축): 구간별 불량률(%) = 구간 불량 / 구간 생산 × 100 — 꺾은선
//   · 두 축 모두 0부터 시작(왜곡 방지). 생산 0인 구간의 불량률은 0 (NaN·Infinity 방지)
// ══════════════════════════════════════════════════════════════
const num0 = (v) => (Number.isFinite(Number(v)) ? Number(v) : 0);
const intervalRate = (tk) => {   // 구간 불량률(%). 생산 0 → 0
  const prod = num0(tk.okCount) + num0(tk.ngCount);
  return prod > 0 ? (num0(tk.ngCount) / prod) * 100 : 0;
};

export function trendChart(container, ticks) {
  const H = 220, P = { l: 46, r: 48, t: 22, b: 28 };
  container.innerHTML = "";
  const { cv, ctx } = makeCanvas(container.offsetWidth || 620, H);
  container.appendChild(cv);
  const tipEl = makeTip(container, "tip");
  let _t = ticks, _hi = null, _raf = null;

  const live = () => (_t ?? []).filter((x) => x && x.okCount != null);
  const geom = () => {
    const W = cv.width / DPR, iw = W - P.l - P.r, ih = H - P.t - P.b, n = Math.max(1, live().length);
    return { W, iw, ih, n, slot: iw / n };
  };

  function draw() {
    const c = T(), { W, iw, ih, n, slot } = geom(), data = live();
    ctx.clearRect(0, 0, W, H);
    ctx.fillStyle = c.plotBg; ctx.fillRect(P.l, P.t, iw, ih);
    if (!data.length) {
      ctx.fillStyle = c.axisLbl; ctx.font = "12px system-ui"; ctx.textAlign = "center";
      ctx.fillText("데이터가 없습니다.", P.l + iw / 2, P.t + ih / 2); return;
    }
    // 좌축: 구간 생산량(EA = OK + NG), 0부터 · 위쪽 15% 여유 · 정수 눈금
    const maxProd = Math.max(0, ...data.map((d) => num0(d.okCount) + num0(d.ngCount)));
    const L = niceScale(0, Math.max(4, maxProd * 1.15), 4);
    const nT = Math.max(1, Math.round(L.hi / L.step));
    // 우축: 불량률(%), 0부터 · 좌축과 같은 눈금 수로 맞춤(격자 공유) · 최대 100
    const rates = data.map(intervalRate);
    let rStep = niceScale(0, Math.max(5, Math.max(0, ...rates) * 1.15), nT).step, rHi = rStep * nT;
    if (rHi > 100) { rHi = 100; rStep = 100 / nT; }
    const YL = (v) => P.t + (1 - v / L.hi) * ih;
    const YR = (v) => P.t + (1 - v / rHi) * ih;
    const CX = (i) => P.l + slot * (i + 0.5);

    // 그리드 + 좌·우 축 눈금 (같은 높이에 정렬)
    ctx.font = "10px system-ui";
    for (let k = 0; k <= nT; k++) {
      const y = P.t + (1 - k / nT) * ih;
      ctx.strokeStyle = c.gridLine; ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(P.l, y); ctx.lineTo(P.l + iw, y); ctx.stroke();
      ctx.fillStyle = c.axisLbl;
      ctx.textAlign = "right"; ctx.fillText(String(Math.round(L.step * k)), P.l - 6, y + 3.5);
      ctx.textAlign = "left"; ctx.fillText(`${+(rStep * k).toFixed(1)}%`, P.l + iw + 6, y + 3.5);
    }
    // 축 제목(단위)
    ctx.font = "600 10px system-ui"; ctx.fillStyle = c.axisLbl;
    ctx.textAlign = "left"; ctx.fillText("생산·불량 (EA)", 2, P.t - 9);            // 좌축 단위
    ctx.fillStyle = c.rateLine; ctx.textAlign = "right"; ctx.fillText("불량률 (%)", W - 2, P.t - 9);   // 우축 단위

    // x축 레이블(겹치지 않게 간격 유지, 현재 구간은 강조)
    const every = Math.max(1, Math.ceil(52 / slot));
    ctx.textAlign = "center"; let last = -999;
    data.forEach((tk, i) => {
      const x = CX(i);
      if (!(i % every === 0 || tk.isCurrent) || x - last < 40) return;
      ctx.fillStyle = tk.isCurrent ? c.current : c.axisLbl;
      ctx.font = tk.isCurrent ? "bold 10px system-ui" : "10px system-ui";
      ctx.fillText(tk.time, x, H - 8); last = x;
    });

    ctx.save(); ctx.beginPath(); ctx.rect(P.l, P.t, iw, ih); ctx.clip();
    if (_hi != null && data[_hi]) {   // 마우스가 올라간 구간 강조
      ctx.fillStyle = c.cross.replace(/[\d.]+\)$/, "0.10)");
      ctx.fillRect(P.l + slot * _hi, P.t, slot, ih);
    }
    // 쌓은 막대 (좌축): 아래 OK + 위 NG → 막대 전체 높이 = 구간 생산량
    const bw = Math.max(3, Math.min(22, slot * 0.62)), base = P.t + ih;
    data.forEach((tk, i) => {
      const ok = num0(tk.okCount), ng = num0(tk.ngCount); if (ok + ng <= 0) return;
      const x = CX(i) - bw / 2, yOk = YL(ok), yAll = YL(ok + ng);
      ctx.globalAlpha = tk.isCurrent ? 0.55 : 1;   // 진행 중 구간은 옅게
      ctx.fillStyle = c.okBar; ctx.fillRect(x, yOk, bw, base - yOk);
      if (ng > 0) { ctx.fillStyle = c.ngLine; ctx.fillRect(x, yAll, bw, yOk - yAll); }
      ctx.globalAlpha = 1;
    });
    // 꺾은선: 구간 불량률 (우축)
    ctx.beginPath(); ctx.strokeStyle = c.rateLine; ctx.lineWidth = 2; ctx.lineJoin = "round";
    rates.forEach((r, i) => (i ? ctx.lineTo(CX(i), YR(r)) : ctx.moveTo(CX(i), YR(r))));
    ctx.stroke();
    rates.forEach((r, i) => {
      ctx.beginPath(); ctx.arc(CX(i), YR(r), i === _hi ? 4.5 : 3, 0, Math.PI * 2);
      ctx.fillStyle = c.plotBg; ctx.fill();
      ctx.strokeStyle = c.rateLine; ctx.lineWidth = 2; ctx.stroke();
    });
    ctx.restore();
    ctx.strokeStyle = c.frame; ctx.lineWidth = 1; ctx.strokeRect(P.l + .5, P.t + .5, iw - 1, ih - 1);
  }
  const sched = () => { cancelAnimationFrame(_raf); _raf = requestAnimationFrame(draw); };

  const showTip = (i, clientPct) => {
    const tk = live()[i];
    if (!tk) { tipEl.hidden = true; return; }
    const c = T(), prod = num0(tk.okCount) + num0(tk.ngCount), cum = tk.tooltip ?? {};
    const [h, m] = String(tk.time).split(":").map(Number), endMin = (h * 60 + m + 30) % 1440;
    const to = `${String(Math.floor(endMin / 60)).padStart(2, "0")}:${String(endMin % 60).padStart(2, "0")}`;
    tipEl.hidden = false;
    tipEl.style.left = `${Math.min(Math.max(clientPct, 14), 84)}%`;
    tipEl.innerHTML = `<b>${tk.time} ~ ${to}${tk.isCurrent ? " (진행 중)" : ""}</b>`
      + `<span><i style="background:${c.okBar};height:8px;width:8px"></i>생산 ${prod}건(EA) <small>= OK ${num0(tk.okCount)} + NG ${num0(tk.ngCount)}</small></span>`
      + `<span><i style="background:${c.ngLine};height:8px;width:8px"></i>불량 ${num0(tk.ngCount)}건(EA)</span>`
      + `<span><i style="background:${c.rateLine}"></i>불량률 ${intervalRate(tk).toFixed(2)}%</span>`
      + `<span class="tip__sub">누적 불량 ${num0(cum.ngCumulative)}건 · 누적 불량률 ${num0(cum.defectRate).toFixed(2)}%</span>`;
  };

  cv.addEventListener("mousemove", (e) => {
    const r = cv.getBoundingClientRect(), { W, n, slot } = geom();
    const mx = (e.clientX - r.left) * (W / (r.width || W));
    const i = Math.floor((mx - P.l) / slot);
    _hi = i >= 0 && i < n && live()[i] ? i : null;
    if (_hi == null) tipEl.hidden = true; else showTip(_hi, ((e.clientX - r.left) / (r.width || W)) * 100);
    sched();
  });
  cv.addEventListener("mouseleave", () => { _hi = null; tipEl.hidden = true; sched(); });
  window.addEventListener("qms:theme", sched);
  sched();
  return {
    update(t) { _t = t; sched(); if (_hi != null) showTip(_hi, parseFloat(tipEl.style.left) || 50); },
    drawNow: draw,
    destroy() { cancelAnimationFrame(_raf); window.removeEventListener("qms:theme", sched); },
  };
}

// ══════════════════════════════════════════════════════════════
// lineChart — 용접 파라미터 트렌드 (시간축 동기화 그룹 지원)
//   opts: { series:[{name,color,points:[{t,v}]}], lower, upper, dec, windowMs, events:[{t,label}], syncGroup }
// ══════════════════════════════════════════════════════════════
const groups = new Map();   // syncGroup 이름 → 차트 집합

export function lineChart(container, opts) {
  const H = 200, HM = 26;
  const P = { l: 54, r: 16, t: 14, b: 24 }, PM = { l: 54, r: 16, t: 4, b: 4 };
  container.innerHTML = "";
  const { cv, ctx } = makeCanvas(container.offsetWidth || 520, H);
  const { cv: mc, ctx: mctx } = makeCanvas(container.offsetWidth || 520, HM, "ew-resize");
  mc.style.marginTop = "4px";
  container.append(cv, mc);
  const tipEl = makeTip(container, "wch-tip");
  const liveBtn = document.createElement("button");
  liveBtn.type = "button"; liveBtn.className = "ch-live"; liveBtn.hidden = true;
  liveBtn.innerHTML = "<i></i>실시간 추종 복귀";
  container.appendChild(liveBtn);

  // 조회 기간(domain)이 있으면 그 밖의 측정값·이벤트는 차트에 넣지 않는다 (시작 <= 시각 <= 종료)
  const inDomain = (o) => {
    if (!o?.domain) return o;
    const [d0, d1] = o.domain, ok = (t) => t >= d0 && t <= d1;
    return { ...o, series: (o.series ?? []).map((s) => ({ ...s, points: s.points.filter((p) => ok(p.t)) })), events: (o.events ?? []).filter((e) => ok(e.t)) };
  };
  let _o = inDomain(opts), _range = null, _freeze = null, _hoverTs = null, _drag = null, _raf = null;
  container._wasDragged = false;

  const allPts = () => (_o.series ?? []).flatMap((s) => s.points);
  const outOf = (p) => {   // 점별 기준(hi/lo) 우선, 없으면 전역 기준
    const up = p.hi ?? _o.upper, lo = p.lo ?? _o.lower;
    return up != null && lo != null && (p.v > up || p.v < lo);
  };
  const extent = () => {   // X축 전체 범위: 조회 기간이 있으면 그 기간 그대로(데이터 유무와 무관)
    if (_o.domain) return _o.domain;
    const p = allPts(); return p.length ? [Math.min(...p.map((x) => x.t)), Math.max(...p.map((x) => x.t))] : [0, 1];
  };
  const autoRange = () => {
    const [t0, t1] = extent();
    return _o.domain || _o.fit ? [t0, t1] : [t1 - (_o.windowMs ?? 2 * 3600e3), t1];
  };
  const range = () => _range ?? _freeze ?? autoRange();       // 수동 범위 > 마우스 오버 고정 > 실시간 추종
  const plotW = () => cv.width / DPR - P.l - P.r;
  const peers = () => [...(groups.get(_o.syncGroup) ?? [])].filter((p) => p !== self);

  function drawMain() {
    const W = cv.width / DPR, c = T(), iw = plotW(), ih = H - P.t - P.b;
    ctx.clearRect(0, 0, W, H);
    ctx.fillStyle = c.plotBg; ctx.fillRect(P.l, P.t, iw, ih);
    const { series = [], lower, upper } = _o;
    if (!allPts().length) {
      ctx.fillStyle = c.axisLbl; ctx.font = "12px system-ui"; ctx.textAlign = "center";
      ctx.fillText("조회 기간에 측정 데이터가 없습니다.", P.l + iw / 2, P.t + ih / 2);
      if (_o.domain) {   // 데이터가 없어도 X축은 조회 기간으로 표시
        const [a, b] = _o.domain;
        ctx.font = "10px system-ui";
        for (let k = 0; k <= 5; k++) ctx.fillText(hhmm(a + ((b - a) * k) / 5), P.l + (iw * k) / 5, H - 7);
      }
      return;
    }
    const [x0, x1] = range(), xs = (x1 - x0) || 1;
    const inView = (p) => p.t >= x0 - xs * 0.02 && p.t <= x1 + xs * 0.02;
    const vis = allPts().filter(inView);
    let vmin = Math.min(...vis.map((p) => p.v), lower ?? Infinity), vmax = Math.max(...vis.map((p) => p.v), upper ?? -Infinity);
    if (!isFinite(vmin)) { vmin = lower ?? 0; vmax = upper ?? 1; }
    const pad = (vmax - vmin) * 0.08 || 0.5;
    const { lo, hi, step } = niceScale(vmin - pad, vmax + pad, 5);
    const dec = _o.dec ?? decimalsFor(step);
    const X = (t) => P.l + ((t - x0) / xs) * iw;
    const Y = (v) => P.t + (1 - (v - lo) / (hi - lo)) * ih;

    // ① 정상 운전 범위 밴드
    if (lower != null && upper != null) {
      const yU = Math.max(P.t, Y(upper)), yL = Math.min(P.t + ih, Y(lower));
      ctx.fillStyle = c.normBand; ctx.fillRect(P.l, yU, iw, yL - yU);
    }
    // ② 그리드 + y축
    ctx.font = "10px system-ui";
    for (let v = lo; v <= hi + step * 1e-6; v += step) {
      const y = Y(v);
      ctx.strokeStyle = c.gridLine; ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(P.l, y); ctx.lineTo(P.l + iw, y); ctx.stroke();
      ctx.fillStyle = c.axisLbl; ctx.textAlign = "right"; ctx.fillText(v.toFixed(dec), P.l - 6, y + 3.5);
    }
    ctx.textAlign = "center";
    for (let k = 0; k <= 5; k++) ctx.fillText(hhmm(x0 + (xs * k) / 5), P.l + (iw * k) / 5, H - 7);

    ctx.save(); ctx.beginPath(); ctx.rect(P.l, P.t, iw, ih); ctx.clip();

    // ③ 수집 중단 구간 (선을 잇지 않고 음영 + '데이터 없음')
    //    결측 기준은 파트(시리즈)별 자기 측정 간격으로 판단, 음영은 모든 파트가 동시에 끊긴 구간만
    const gapOf = new Map(series.map((s) => [s, gapThreshold(s.points.map((p) => p.t))]));
    const gap = Math.max(...[...gapOf.values()].filter(isFinite), 120000);
    const times = [...new Set(allPts().map((p) => p.t))].sort((a, b) => a - b);
    for (let i = 1; i < times.length; i++) {
      if (times[i] - times[i - 1] <= gap) continue;
      const gx0 = X(times[i - 1]), gx1 = X(times[i]);
      if (gx1 < P.l || gx0 > P.l + iw) continue;
      ctx.fillStyle = c.gapFill; ctx.fillRect(gx0, P.t, gx1 - gx0, ih);
      if (gx1 - gx0 > 70) { ctx.fillStyle = c.gapLbl; ctx.font = "11px system-ui"; ctx.fillText("데이터 없음", (gx0 + gx1) / 2, P.t + ih / 2); }
    }

    // ④ 기준선 (UCL/LCL)
    if (lower != null && upper != null) {
      ctx.setLineDash([4, 4]); ctx.strokeStyle = c.limitLine; ctx.lineWidth = 1;
      [upper, lower].forEach((v) => { ctx.beginPath(); ctx.moveTo(P.l, Y(v)); ctx.lineTo(P.l + iw, Y(v)); ctx.stroke(); });
      ctx.setLineDash([]);
    }

    // ⑤ 알람 이벤트 마커
    (_o.events ?? []).forEach((ev) => {
      const x = X(ev.t); if (x < P.l || x > P.l + iw) return;
      ctx.setLineDash([2, 3]); ctx.strokeStyle = c.event; ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(x, P.t); ctx.lineTo(x, P.t + ih); ctx.stroke(); ctx.setLineDash([]);
      ctx.fillStyle = c.eventMark; ctx.beginPath(); ctx.moveTo(x - 4, P.t); ctx.lineTo(x + 4, P.t); ctx.lineTo(x, P.t + 6); ctx.closePath(); ctx.fill();
    });

    // ⑥ 데이터 라인: 정상 색으로 그린 뒤, 기준 밖 영역만 빨간색으로 덧그림 (구간 동적 변환)
    const paths = series.map((s) => {
      const pts = s.points.filter(inView);
      const ds = lttb(pts, Math.max(50, Math.floor(iw)));
      return { s, raw: pts, ds };
    });
    const stroke = (pts, color, w, g = gap) => {
      ctx.beginPath(); ctx.strokeStyle = color; ctx.lineWidth = w; ctx.lineJoin = "round"; ctx.lineCap = "round";
      pts.forEach((p, k) => {
        if (k && p.t - pts[k - 1].t > g) ctx.moveTo(X(p.t), Y(p.v));   // 결측 구간은 끊는다
        else k ? ctx.lineTo(X(p.t), Y(p.v)) : ctx.moveTo(X(p.t), Y(p.v));
      });
      ctx.stroke();
    };
    paths.forEach(({ s, ds }) => stroke(ds, resolveColor(s.color), 2, gapOf.get(s)));
    if (lower != null && upper != null) {
      ctx.save(); ctx.beginPath();
      ctx.rect(P.l, P.t, iw, Math.max(0, Y(upper) - P.t));                 // UCL 위
      ctx.rect(P.l, Y(lower), iw, Math.max(0, P.t + ih - Y(lower)));        // LCL 아래
      ctx.clip();
      paths.forEach(({ s, ds }) => stroke(ds, c.alarm, 2.4, gapOf.get(s)));
      ctx.restore();
      paths.forEach(({ raw }) => raw.filter(outOf).forEach((p) => {   // 원본 기준(다운샘플로 놓치지 않게)
        ctx.beginPath(); ctx.fillStyle = c.alarm; ctx.arc(X(p.t), Y(p.v), 3.2, 0, Math.PI * 2); ctx.fill();
        ctx.strokeStyle = c.ring; ctx.lineWidth = 1.2; ctx.stroke();
      }));
    }

    // ⑦ 크로스헤어 (자기 또는 동기화된 다른 차트의 마우스 위치)
    if (_hoverTs != null) {
      const hx = X(_hoverTs);
      ctx.strokeStyle = c.cross; ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(hx, P.t); ctx.lineTo(hx, P.t + ih); ctx.stroke();
      paths.forEach(({ s, raw }) => {
        const n = nearest(raw, _hoverTs); if (!n) return;
        const bad = outOf(n);
        ctx.beginPath(); ctx.fillStyle = bad ? c.alarm : resolveColor(s.color); ctx.arc(X(n.t), Y(n.v), 4.5, 0, Math.PI * 2); ctx.fill();
        ctx.strokeStyle = c.ring; ctx.lineWidth = 1.5; ctx.stroke();
      });
    }
    ctx.restore();

    // ⑧ 플롯 테두리 + 기준선 레이블
    ctx.strokeStyle = c.frame; ctx.lineWidth = 1; ctx.strokeRect(P.l + .5, P.t + .5, iw - 1, ih - 1);
    if (lower != null && upper != null) {
      ctx.font = "600 9.5px system-ui"; ctx.textAlign = "right"; ctx.fillStyle = c.limitLbl;
      [[upper, "UCL", -4], [lower, "LCL", 11]].forEach(([v, l, dy]) => {
        const y = Y(v); if (y > P.t + 8 && y < P.t + ih - 4) ctx.fillText(`${l} ${v}`, P.l + iw - 6, y + dy);
      });
    }
    liveBtn.hidden = !_range;
    liveBtn.innerHTML = _o.live === false ? "<i></i>조회 기간 전체 보기" : "<i></i>실시간 추종 복귀";
  }

  function drawMini() {
    const W = mc.width / DPR, c = T(), iw = W - PM.l - PM.r, ih = HM - PM.t - PM.b;
    mctx.clearRect(0, 0, W, HM);
    mctx.fillStyle = c.plotBg; mctx.fillRect(PM.l, PM.t, iw, ih);
    const pts = allPts(); if (!pts.length) return;
    const [t0, t1] = extent(), ts = (t1 - t0) || 1;
    const vmin = Math.min(...pts.map((p) => p.v)), vmax = Math.max(...pts.map((p) => p.v));
    const X = (t) => PM.l + ((t - t0) / ts) * iw, Y = (v) => PM.t + (1 - (v - vmin) / ((vmax - vmin) || 1)) * ih;
    mctx.globalAlpha = 0.55;
    (_o.series ?? []).forEach((s) => {
      const gap = gapThreshold(s.points.map((p) => p.t));
      const d = lttb(s.points, Math.floor(iw));
      mctx.beginPath(); mctx.strokeStyle = resolveColor(s.color); mctx.lineWidth = 1;
      d.forEach((p, k) => (k && p.t - d[k - 1].t <= gap ? mctx.lineTo(X(p.t), Y(p.v)) : mctx.moveTo(X(p.t), Y(p.v))));
      mctx.stroke();
    });
    mctx.globalAlpha = 1;
    const [x0, x1] = range(), a = Math.max(PM.l, X(x0)), b = Math.min(PM.l + iw, X(x1));
    mctx.fillStyle = c.miniWin; mctx.fillRect(a, PM.t, b - a, ih);
    mctx.strokeStyle = c.miniBdr; mctx.lineWidth = 1.5; mctx.strokeRect(a, PM.t + .75, b - a, ih - 1.5);
    mctx.strokeStyle = c.frame; mctx.lineWidth = 1; mctx.strokeRect(PM.l + .5, PM.t + .5, iw - 1, ih - 1);
  }

  function nearest(pts, t) {
    let n = null;
    for (const p of pts) if (!n || Math.abs(p.t - t) < Math.abs(n.t - t)) n = p;
    return n;
  }

  function showTip(t) {
    if (t == null) { tipEl.hidden = true; return; }
    const [x0, x1] = range(), c = T();
    const rows = (_o.series ?? []).map((s) => {
      const n = nearest(s.points.filter((p) => p.t >= x0 && p.t <= x1), t); if (!n) return "";
      const bad = outOf(n);
      return `<span><i style="background:${resolveColor(s.color)}"></i>${s.name}<b class="${bad ? "is-bad" : ""}">${n.v.toFixed(_o.dec ?? 2)}${bad ? " ▲" : ""}</b></span>`;
    }).filter(Boolean);
    const tol = ((x1 - x0) / plotW()) * 6;   // 마커 ±6px 이내 알람
    const evs = (_o.events ?? []).filter((e) => Math.abs(e.t - t) <= tol).map((e) => `<span class="wch-tip__ev">⚠ ${hhmm(e.t)} ${e.label}</span>`);
    if (!rows.length && !evs.length) { tipEl.hidden = true; return; }
    tipEl.hidden = false;
    const pct = ((P.l + ((t - x0) / ((x1 - x0) || 1)) * plotW()) / (cv.width / DPR)) * 100;
    tipEl.style.left = `${Math.min(Math.max(pct, 20), 80)}%`;
    tipEl.innerHTML = `<b>${new Date(t).toTimeString().slice(0, 8)}</b>${rows.join("")}${evs.join("")}`;
    void c;
  }

  const sched = () => { cancelAnimationFrame(_raf); _raf = requestAnimationFrame(() => { drawMain(); drawMini(); }); };
  const tsAt = (clientX) => {
    const r = cv.getBoundingClientRect(), W = cv.width / DPR, mx = (clientX - r.left) * (W / r.width);
    const [x0, x1] = range();
    return x0 + ((Math.max(P.l, Math.min(P.l + plotW(), mx)) - P.l) / plotW()) * (x1 - x0);
  };
  // 그룹 동기화
  const setHover = (t, broadcast) => {
    if (t != null && !_range && !_freeze) _freeze = autoRange();   // 마우스 오버 중 자동 스크롤 정지
    if (t == null) _freeze = null;
    _hoverTs = t; showTip(t); sched();
    if (broadcast) peers().forEach((p) => p._hover(t));
  };
  const setRange = (r, broadcast) => {
    if (r) {   // 확대/이동 범위는 실제 데이터 구간 안으로 제한 (미래·데이터 없는 과거로 벗어나지 않게)
      const [t0, t1] = extent(), full = Math.max(t1 - t0, 60e3);
      let span = Math.min(r[1] - r[0], full), a = Math.max(t0, Math.min(r[0], t1 - span));
      r = [a, a + span];
    }
    _range = r; _freeze = null; sched();
    if (broadcast) peers().forEach((p) => p._range(r));
  };

  cv.addEventListener("mousemove", (e) => {
    if (_drag?.type === "pan") {
      const r = cv.getBoundingClientRect(), W = cv.width / DPR, mx = (e.clientX - r.left) * (W / r.width);
      if (Math.abs(mx - _drag.x) > 3) _drag.moved = true;
      const dt = ((_drag.x - mx) / plotW()) * (_drag.r[1] - _drag.r[0]);
      setRange([_drag.r[0] + dt, _drag.r[1] + dt], true);
    }
    setHover(tsAt(e.clientX), true);
  });
  cv.addEventListener("mouseleave", () => { if (!_drag) setHover(null, true); });
  cv.addEventListener("mousedown", (e) => {
    e.preventDefault();
    _drag = { type: "pan", x: (e.clientX - cv.getBoundingClientRect().left) * ((cv.width / DPR) / cv.getBoundingClientRect().width), r: range(), moved: false };
    container._wasDragged = false; cv.style.cursor = "grabbing";
  });
  const onUp = () => {
    if (!_drag) return;
    if (_drag.moved) { container._wasDragged = true; setTimeout(() => (container._wasDragged = false), 50); }
    _drag = null; cv.style.cursor = "crosshair";
  };
  window.addEventListener("mouseup", onUp);
  cv.addEventListener("wheel", (e) => {
    e.preventDefault();
    const [x0, x1] = range(), span = x1 - x0, t = tsAt(e.clientX);
    const ns = Math.max(60e3, Math.min(span * (e.deltaY > 0 ? 1.25 : 0.8), 24 * 3600e3));
    const ratio = (t - x0) / (span || 1);
    setRange([t - ratio * ns, t + (1 - ratio) * ns], true);
  }, { passive: false });
  cv.addEventListener("dblclick", () => setRange(null, true));
  liveBtn.addEventListener("click", (e) => { e.stopPropagation(); setRange(null, true); });

  // 미니맵: 클릭 위치로 이동 / 드래그로 이동
  const miniMove = (clientX) => {
    const r = mc.getBoundingClientRect(), W = mc.width / DPR, mx = (clientX - r.left) * (W / r.width);
    const [t0, t1] = extent(), [x0, x1] = range(), span = x1 - x0;
    const center = t0 + ((mx - PM.l) / (W - PM.l - PM.r)) * (t1 - t0);
    let a = center - span / 2; a = Math.max(t0, Math.min(a, t1 - span));
    setRange([a, a + span], true);
  };
  mc.addEventListener("mousedown", (e) => { e.preventDefault(); e.stopPropagation(); _drag = { type: "mini" }; miniMove(e.clientX); });
  const onMove = (e) => { if (_drag?.type === "mini") miniMove(e.clientX); };
  window.addEventListener("mousemove", onMove);
  window.addEventListener("qms:theme", sched);

  const self = {
    _hover: (t) => setHover(t, false),
    _range: (r) => setRange(r, false),
    update(o) {   // 주기 갱신: 데이터·기간 끝만 갱신 (기간 선택을 바꾸면 화면이 차트를 새로 만든다)
      _o = inDomain(o);
      sched(); if (_hoverTs != null) showTip(_hoverTs);
    },
    drawNow() { drawMain(); },
    destroy() {
      cancelAnimationFrame(_raf);
      window.removeEventListener("mouseup", onUp); window.removeEventListener("mousemove", onMove);
      window.removeEventListener("qms:theme", sched);
      groups.get(_o.syncGroup)?.delete(self);
    },
  };
  if (_o.syncGroup) {
    if (!groups.has(_o.syncGroup)) groups.set(_o.syncGroup, new Set());
    const g = groups.get(_o.syncGroup);
    const other = [...g][0];
    g.add(self);
    if (other) { /* 이미 열린 차트의 확대 범위를 이어받는다 */ }
  }
  sched();
  return self;
}

// ══════════════════════════════════════════════════════════════
// chartImage — 파일 추출(PDF/Excel)용 차트 이미지
//   현업 표준: 화면 캡처가 아니라 '흰 배경 · 2배 해상도'로 다시 그려 PNG(Base64)로 변환. 제목·범례·관리 기준 포함
// ══════════════════════════════════════════════════════════════
export function chartImage(kind, data, { title = "", width = 1100, scale = 2 } = {}) {
  const prev = DPR;
  DPR = scale; _export = true;
  const box = document.createElement("div");
  box.style.cssText = `position:fixed;left:-30000px;top:0;width:${width}px`;
  document.body.appendChild(box);
  try {
    const ch = kind === "trend" ? trendChart(box, data) : lineChart(box, { ...data, fit: true, syncGroup: undefined });
    ch.drawNow();
    const src = box.querySelector("canvas"), head = 34;
    const out = document.createElement("canvas");
    out.width = src.width; out.height = src.height + head * scale;
    const g = out.getContext("2d");
    g.fillStyle = "#ffffff"; g.fillRect(0, 0, out.width, out.height);
    g.scale(scale, scale);
    g.textBaseline = "middle"; g.fillStyle = "#1e293b"; g.font = "bold 14px system-ui"; g.textAlign = "left";
    g.fillText(title, 12, head / 2);
    const items = kind === "trend" ? [["생산 OK (EA)", "#9fb4cc"], ["불량 NG (EA)", "#c62828"], ["불량률 (%)", "#1e293b"]] : (data.series ?? []).map((s) => [s.name, resolveColor(s.color)]);
    if (data.lower != null && data.upper != null) items.push([`관리 기준 ${data.lower} ~ ${data.upper}`, "rgba(200,40,40,.7)"]);
    if (data.events?.length) items.push([`알람 ${data.events.length}건`, "#d97706"]);
    g.font = "12px system-ui"; g.textAlign = "right";
    let x = out.width / scale - 12;
    for (const [name, col] of [...items].reverse()) {
      g.fillStyle = "#334155"; g.fillText(name, x, head / 2);
      x -= g.measureText(name).width + 6;
      g.fillStyle = col; g.fillRect(x - 16, head / 2 - 1.5, 16, 3);
      x -= 30;
    }
    g.setTransform(1, 0, 0, 1, 0, 0);
    g.drawImage(src, 0, head * scale);
    ch.destroy();
    return out.toDataURL("image/png");
  } finally {
    box.remove(); DPR = prev; _export = false;
  }
}

// ══════════════════════════════════════════════════════════════
// barChart — 불량 유형 분포 (기존 색 유지)
// ══════════════════════════════════════════════════════════════
const BAR_COLS = ["#b23535", "#c56a6a", "#27405c", "#3b5c82", "#6b8fb5", "#8faacc"];
export function barChart(bars) {
  if (!bars?.length) return `<div class="msg">오늘 발생한 불량 유형이 없습니다.</div>`;
  const max = Math.max(1, ...bars.map((b) => b.ratio));
  return `<div class="bars">${bars.map((b, i) =>
    `<div class="bar"><span class="bar__val">${b.count}건</span>
      <span class="bar__col" style="height:${Math.max(14, Math.round((b.ratio / max) * 150))}px;background:${BAR_COLS[i] ?? BAR_COLS[3]}" title="${b.ratio}%"></span>
      <span class="bar__label">${b.label}</span></div>`).join("")}</div>`;
}
