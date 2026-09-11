"""필기 샘플만 나눔 펜 윤곽선으로 변환한다. 실행 전 fonttools가 필요하다.

실행: python3 docs/design/export-handwriting.py
UI와 성경 원문은 텍스트로 유지하고 원본 SVG는 변경하지 않는다.
"""

from pathlib import Path
import xml.etree.ElementTree as ET

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont


BASE = Path(__file__).resolve().parent / "assets"
NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", NS)
font = TTFont(BASE / "fonts/NanumPenScript-Regular.ttf")
glyphs = font.getGlyphSet()
cmap = font.getBestCmap()
units = font["head"].unitsPerEm
output = BASE / "figma-outlined"
output.mkdir(exist_ok=True)
count = 0

for source in sorted((BASE / "figma").glob("*.svg")):
    tree = ET.parse(source)
    root = tree.getroot()
    for parent in list(root.iter()):
        for node in list(parent):
            if node.tag != f"{{{NS}}}text" or node.get("data-role") != "handwriting":
                continue
            text = node.text or ""
            names = []
            for character in text:
                if ord(character) not in cmap:
                    raise ValueError(f"지원하지 않는 글자: {source.name}: {character!r}")
                names.append(cmap[ord(character)])
            scale = float(node.get("font-size", "27")) / units
            width = sum(glyphs[name].width for name in names) * scale
            x = float(node.get("x", "0"))
            y = float(node.get("y", "0"))
            anchor = node.get("text-anchor")
            if anchor == "middle":
                x -= width / 2
            elif anchor == "end":
                x -= width
            attrs = {key: value for key, value in node.attrib.items()
                     if key not in {"x", "y", "font-family", "font-size", "text-anchor"}}
            attrs.update({"data-name": f"필기 · {text}", "aria-label": text})
            group = ET.Element(f"{{{NS}}}g", attrs)
            ET.SubElement(group, f"{{{NS}}}title").text = text
            position = x
            for name in names:
                pen = SVGPathPen(glyphs)
                glyphs[name].draw(pen)
                commands = pen.getCommands()
                if commands:
                    ET.SubElement(group, f"{{{NS}}}path", {
                        "d": commands,
                        "transform": f"translate({position:.4f} {y}) scale({scale:.6f} {-scale:.6f})",
                    })
                position += glyphs[name].width * scale
            index = list(parent).index(node)
            parent.remove(node)
            parent.insert(index, group)
            count += 1
    tree.write(output / source.name, encoding="unicode")

print(f"SVG {len(list(output.glob('*.svg')))}개 내보내기 · 필기 {count}줄 윤곽선 변환")
