# Generates the round brilliant-cut blue gem used as the Meth icon's badge in comparison.html.
# Top view: octagonal table, 8 star facets, 8 kite (bezel) facets, 16 upper-girdle facets,
# lit from the top left with smooth per-facet gradients, a gloss highlight and a sparkle.
import math, re, sys

C = (50, 50)
R_GIRDLE, R_STAR, R_TABLE = 45, 31.5, 19
LIGHT = math.radians(225)  # light comes from the top left (SVG y points down)

def pt(r, deg):
    a = math.radians(deg - 90)
    return (C[0] + r * math.cos(a), C[1] + r * math.sin(a))

def mix(c0, c1, t):
    return tuple(round(a + (b - a) * t) for a, b in zip(c0, c1))

PAL = [(0.0, (4, 36, 110)), (0.3, (8, 78, 190)), (0.55, (26, 132, 245)), (0.8, (104, 196, 255)), (1.0, (222, 246, 255))]
def tone(t):
    t = max(0, min(1, t))
    for (t0, c0), (t1, c1) in zip(PAL, PAL[1:]):
        if t <= t1:
            return '#%02x%02x%02x' % mix(c0, c1, (t - t0) / (t1 - t0))
    return '#def6ff'

def facing(deg, bias=0):
    # 1 when the facet faces the light, 0 when it faces away.
    a = math.radians(deg - 90)
    return (math.cos(a - LIGHT) + 1) / 2 + bias

f = lambda p: f'{p[0]:.2f},{p[1]:.2f}'
defs, shapes, n = [], [], [0]

def facet(points, deg, lo, hi):
    # Each facet gets its own gradient running across it, brighter on the lit side.
    n[0] += 1
    gid = f'g{n[0]}'
    a = math.radians(deg - 90)
    x1, y1 = 0.5 + 0.5 * math.cos(a + math.pi), 0.5 + 0.5 * math.sin(a + math.pi)
    x2, y2 = 0.5 + 0.5 * math.cos(a), 0.5 + 0.5 * math.sin(a)
    t = facing(deg)
    defs.append(f'<linearGradient id="{gid}" x1="{x1:.2f}" y1="{y1:.2f}" x2="{x2:.2f}" y2="{y2:.2f}">'
                f'<stop offset="0" stop-color="{tone(lo + (hi - lo) * t + .12)}"/>'
                f'<stop offset="1" stop-color="{tone(lo + (hi - lo) * t - .1)}"/></linearGradient>')
    shapes.append(f'<polygon points="{" ".join(f(p) for p in points)}" fill="url(#{gid})"/>')

table = [pt(R_TABLE, 22.5 + 45 * k) for k in range(8)]
stars = [pt(R_STAR, 45 * k) for k in range(8)]           # star points sit between table corners

for k in range(8):
    # Kite (bezel) facet around each table corner.
    tc = table[k]
    deg = 22.5 + 45 * k
    kite = [tc, stars[k], pt(R_GIRDLE, deg), stars[(k + 1) % 8]]
    facet(kite, deg, .25, .95)
    # Star facet between two table corners.
    facet([table[k - 1], table[k], stars[k]], 45 * k, .35, 1.0)
    # Two upper-girdle facets fill the rim between neighbouring kites, meeting at this star point.
    facet([stars[k], pt(R_GIRDLE, 45 * k - 22.5), pt(R_GIRDLE, 45 * k)], 45 * k - 11, .15, .82)
    facet([stars[k], pt(R_GIRDLE, 45 * k), pt(R_GIRDLE, 45 * k + 22.5)], 45 * k + 11, .15, .82)

outline = [pt(R_GIRDLE, 22.5 * k) for k in range(16)]
svg = f'''<svg class="crystal" viewBox="0 0 100 100" aria-hidden="true">
      <defs>
        <radialGradient id="tbl" cx=".38" cy=".34" r=".8"><stop offset="0" stop-color="#e9fbff"/><stop offset=".45" stop-color="#8fd6ff"/><stop offset="1" stop-color="#2a8cf2"/></radialGradient>
        <linearGradient id="side" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#1c6ad8"/><stop offset="1" stop-color="#062a78"/></linearGradient>
        <radialGradient id="gloss" cx=".3" cy=".22" r=".55"><stop offset="0" stop-color="#fff" stop-opacity=".75"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>
        {''.join(defs)}
      </defs>
      <polygon points="{' '.join(f((x + 1.4, y + 2.6)) for x, y in outline)}" fill="url(#side)"/>
      {''.join(shapes)}
      <polygon points="{' '.join(f(p) for p in table)}" fill="url(#tbl)"/>
      <g fill="none" stroke="rgba(255,255,255,.35)" stroke-width=".55" stroke-linejoin="round">
        <polygon points="{' '.join(f(p) for p in table)}"/>
        {''.join(f'<path d="M{f(table[k])} L{f(stars[k])} L{f(table[k-1])} M{f(stars[k])} L{f(pt(R_GIRDLE, 45*k))}"/>' for k in range(8))}
        {''.join(f'<path d="M{f(table[k])} L{f(pt(R_GIRDLE, 22.5 + 45*k))}"/>' for k in range(8))}
      </g>
      <polygon points="{' '.join(f(p) for p in outline)}" fill="none" stroke="rgba(255,255,255,.7)" stroke-width="1" stroke-linejoin="round"/>
      <circle cx="50" cy="50" r="{R_GIRDLE}" fill="url(#gloss)"/>
      <path d="M33 23 l1.6 5.2 5.2 1.6 -5.2 1.6 -1.6 5.2 -1.6 -5.2 -5.2 -1.6 5.2 -1.6z" fill="#fff" opacity=".95"/>
    </svg>'''

html = open('comparison.html').read()
i = html.index('<svg class="crystal"'); j = html.index('</svg>', i) + len('</svg>')
html = html[:i] + svg + html[j:]
html = re.sub(r'\.crystal\{[^}]*\}', '.crystal{position:absolute;right:-10px;bottom:-12px;width:112px;height:112px;filter:drop-shadow(0 10px 14px rgba(8,40,110,.32)) drop-shadow(0 2px 4px rgba(8,40,110,.28))}', html)
open('comparison.html', 'w').write(html)
