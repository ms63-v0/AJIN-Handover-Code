from fontTools.ttLib import TTCollection
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
import glob
def load(path, fam="Noto Sans CJK KR"):
    for f in TTCollection(path).fonts:
        names=[n.toUnicode() for n in f['name'].names if n.nameID in (1,16)]
        if any(fam in n for n in names): return f
    raise SystemExit("font not found "+path)
BOLD=load('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc')
REG=load('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')
def path(font,text,x,y,size,track=0):
    gs=font.getGlyphSet(); cmap=font.getBestCmap(); upm=font['head'].unitsPerEm
    hmtx=font['hmtx']; s=size/upm; pen=SVGPathPen(gs); cx=x
    for ch in text:
        g=cmap.get(ord(ch)); 
        if g is None: continue
        tp=TransformPen(pen,(s,0,0,-s,cx,y)); gs[g].draw(tp)
        cx+=hmtx[g][0]*s+track
    return pen.getCommands(), cx-x
W,H=960,260
TITLE="AJIN HW 품질관리시스템"; SUB="용접·비전 품질 데이터 조회·관리"
def make(bg,stroke,ct,cs,acc,name):
    t,tw=path(BOLD,TITLE,56,142,72,-0.6)
    s,sw=path(REG,SUB,56,204,36)
    print(name,'title width',round(tw),'sub width',round(sw),'limit',W-112)
    svg=f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img" aria-labelledby="t d">
  <title id="t">{TITLE}</title>
  <desc id="d">{SUB}</desc>
  <rect x="0.5" y="0.5" width="{W-1}" height="{H-1}" fill="#{bg}" stroke="#{stroke}"/>
  <rect x="56" y="56" width="48" height="5" fill="#{acc}"/>
  <path fill="#{ct}" d="{t}"/>
  <path fill="#{cs}" d="{s}"/>
</svg>
'''
    open(f'docs/assets/banner-{name}.svg','w',encoding='utf-8').write(svg)
make('F5F5F7','E0E0E0','1D1D1F','333333','0066CC','light')
make('272729','3A3A3C','FFFFFF','CCCCCC','2997FF','dark')
