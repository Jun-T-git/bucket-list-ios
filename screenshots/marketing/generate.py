#!/usr/bin/env python3
"""Generate App Store marketing screenshots (1284x2778, iPhone 6.5"/6.7").

Composites the raw app captures in ../appstore-6.9inch/ onto a branded
background with headline/subtext (and, for screen 1, a share-button callout),
rendering each via headless Google Chrome to ../appstore-marketing/.

Refresh the raw captures first (see ../README.md), then run:
    python3 screenshots/marketing/generate.py
"""
import base64, subprocess, pathlib
from PIL import Image

# The composite is designed/rendered at 1320x2868 (iPhone 6.9"), then downscaled
# to the App Store Connect target below. 1284x2778 (iPhone 6.5"/6.7") is accepted
# by every current iPhone screenshot slot; 1320x2868 only fits the 6.9" slot.
TARGET = (1284, 2778)

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
RAW  = HERE.parent / "appstore-6.9inch"
OUT  = HERE.parent / "appstore-marketing"
ICON = ROOT / "BucketList/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

def b64(p): return base64.b64encode(pathlib.Path(p).read_bytes()).decode()

# Each screen: raw image, headline, subtext, caption top offset, and whether to
# show the "share button -> Wishes" callout (screen 1 only).
SCREENS = [
    dict(img="05-share.png",     captop=150, callout=True,
         head="他のアプリからでも、<br>ワンタップで保存。",
         sub ="気になったお店や場所も、共有ボタンから。"),
    dict(img="01-home.png",      captop=184, callout=False,
         head="集めた「いつか」を、<br>ちゃんと叶える。",
         sub ="やりたいことも、行きたい場所も。<br>ひとつのリストで、ちゃんと消化。"),
    dict(img="06-aicapture.png", captop=184, callout=False,
         head="面倒な入力は、<br>AIにおまかせ。",
         sub ="URLからAIが自動で情報を収集・整理。<br>手入力の手間は、もういりません。"),
    dict(img="02-report.png",    captop=184, callout=False,
         head="叶えた数が、<br>増えていく。",
         sub ="希望のペースに合わせて、<br>AIが計画も、そっと提案。"),
]

CALLOUT = """
<div class="callout">
  <div class="sbtn"><svg viewBox="0 0 24 24"><path d="M12 14.5 V3.6"/><path d="M8.4 7.2 L12 3.4 L15.6 7.2"/><path d="M7.2 10 H5.4 V20.4 H18.6 V10 H16.8"/></svg></div>
  <div class="arw">&#8594;</div>
  <img class="wic" src="data:image/png;base64,__ICON__">
  <div class="wlab">Wishes</div>
</div>""".replace("__ICON__", b64(ICON))

TEMPLATE = """<!doctype html><html lang="ja"><head><meta charset="utf-8">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Zen+Kaku+Gothic+New:wght@500;700;900&display=swap" rel="stylesheet">
<style>
*{margin:0;box-sizing:border-box}
html,body{width:1320px;height:2868px}
body{font-family:'Zen Kaku Gothic New','Hiragino Sans',sans-serif;-webkit-font-smoothing:antialiased}
.canvas{position:relative;width:1320px;height:2868px;overflow:hidden;background:linear-gradient(180deg,#EAF6EF 0%,#DBEEE1 100%)}
.blobA{position:absolute;width:1100px;height:900px;left:-260px;top:-280px;border-radius:50%;background:radial-gradient(closest-side,rgba(122,196,149,.40),transparent 70%);filter:blur(20px)}
.blobB{position:absolute;width:900px;height:820px;right:-240px;top:90px;border-radius:50%;background:radial-gradient(closest-side,rgba(255,183,156,.30),transparent 70%);filter:blur(24px)}
.cap{position:absolute;top:__CAPTOP__px;left:118px;right:118px;text-align:center}
.head{font-size:83px;font-weight:900;line-height:1.29;color:#12281C;letter-spacing:.01em}
.sub{font-size:34px;font-weight:500;line-height:1.6;color:#54685e;margin-top:24px}
.callout{position:absolute;left:50%;top:474px;transform:translateX(-50%);display:flex;align-items:center;gap:28px;background:#fff;border-radius:42px;padding:24px 44px;box-shadow:0 30px 64px rgba(18,45,32,.20),0 10px 22px rgba(18,45,32,.10);border:1px solid rgba(18,45,32,.05);z-index:5}
.sbtn{width:96px;height:96px;border-radius:26px;background:#EEF5F0;display:flex;align-items:center;justify-content:center}
.sbtn svg{width:52px;height:52px;stroke:#2E8855;fill:none;stroke-width:2.1;stroke-linecap:round;stroke-linejoin:round}
.arw{font-size:48px;color:#b3bdb6}
.wic{width:96px;height:96px;border-radius:24px;box-shadow:0 6px 16px rgba(0,0,0,.14)}
.wlab{font-size:38px;font-weight:900;color:#12281C;letter-spacing:.02em}
.phone{position:absolute;left:50%;top:648px;transform:translateX(-50%);width:1012px;border-radius:100px;padding:15px;background:linear-gradient(160deg,#243128,#0d1512);box-shadow:0 46px 100px rgba(18,45,32,.30),0 16px 40px rgba(18,45,32,.16)}
.screen{position:relative;border-radius:85px;overflow:hidden;box-shadow:inset 0 0 0 2px rgba(255,255,255,.06)}
.screen img{display:block;width:100%}
.gloss{position:absolute;inset:0;border-radius:85px;pointer-events:none;background:linear-gradient(115deg,rgba(255,255,255,.10) 0%,rgba(255,255,255,0) 20%)}
</style></head><body><div class="canvas">
<div class="blobA"></div><div class="blobB"></div>
<div class="cap"><div class="head">__HEAD__</div><div class="sub">__SUB__</div></div>
__CALLOUT__
<div class="phone"><div class="screen"><img src="data:image/png;base64,__IMG__"><div class="gloss"></div></div></div>
</div></body></html>"""

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for i, s in enumerate(SCREENS, 1):
        html = (TEMPLATE
                .replace("__CAPTOP__", str(s["captop"]))
                .replace("__HEAD__", s["head"])
                .replace("__SUB__", s["sub"])
                .replace("__CALLOUT__", CALLOUT if s["callout"] else "")
                .replace("__IMG__", b64(RAW / s["img"])))
        htmlfile = OUT / f"_screen{i}.html"
        htmlfile.write_text(html, encoding="utf-8")
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--force-device-scale-factor=1", "--window-size=1320,2868",
                        "--virtual-time-budget=6000", "--default-background-color=00000000",
                        f"--screenshot={OUT}/{i:02d}.png", f"file://{htmlfile}"],
                       check=True, capture_output=True)
        htmlfile.unlink()
        # Downscale to the App Store Connect target size.
        out = OUT / f"{i:02d}.png"
        Image.open(out).convert("RGB").resize(TARGET, Image.LANCZOS).save(out)
        print(f"rendered {i:02d}.png {TARGET[0]}x{TARGET[1]}")

if __name__ == "__main__":
    main()
