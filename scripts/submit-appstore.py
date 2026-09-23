#!/usr/bin/env python3
"""submit-appstore.py — Wishes を App Store 審査に提出する（App Store Connect API）

TestFlight 配信（scripts/release-testflight.sh）でアップロード済みのビルドを、
バージョン作成 → 「このバージョンの新機能」→ ビルド紐付け → 審査提出 まで一括で行う。

使い方:
  scripts/submit-appstore.py status                       # バージョン/ビルドの状態を表示
  scripts/submit-appstore.py submit --notes notes.txt     # pbxproj の version/build を提出
  scripts/submit-appstore.py submit --notes notes.txt --version 1.1.0 --build 9
  scripts/submit-appstore.py submit --notes notes.txt --dry-run   # 提出手前まで（提出はしない）
  scripts/submit-appstore.py submit --notes notes.txt --release MANUAL   # 承認後に手動公開

前提:
  - PyJWT（`pip3 install pyjwt`）。requests は不要（標準ライブラリのみ）。
  - API キー（.p8）が ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8 にあること。
  - 認証情報は環境変数か scripts/asc.env（gitignore 済み）から読む:
      ASC_ISSUER_ID=...  ASC_KEY_ID=...  ASC_APP_ID=...
    雛形は scripts/asc.env.example。

よくある失敗と対処:
  - "build N is still PROCESSING" → アップロード直後。--wait で処理完了まで待つ（既定 ON、最大30分）。
  - "version X is READY_FOR_DISTRIBUTION" → そのバージョンは公開済み。release-testflight.sh --version で上げて再配信。
  - "version X is WAITING_FOR_REVIEW / IN_REVIEW" → 提出済み。差し替えるなら ASC で提出を取り下げてから。
  - 401 → キーの失効/権限不足。ASC → ユーザとアクセス → 統合 → App Store Connect API で確認。
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

try:
    import jwt
except ImportError:
    sys.exit("PyJWT が必要です: pip3 install pyjwt")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBX = os.path.join(ROOT, "BucketList.xcodeproj", "project.pbxproj")
BASE = "https://api.appstoreconnect.apple.com/v1"

# 提出可能（＝メタデータ編集可能）な状態
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "INVALID_BINARY"}


# MARK: - 認証

def load_env():
    path = os.path.join(ROOT, "scripts", "asc.env")
    if os.path.exists(path):
        for line in open(path):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"'))
    missing = [k for k in ("ASC_ISSUER_ID", "ASC_KEY_ID", "ASC_APP_ID") if not os.environ.get(k)]
    if missing:
        sys.exit(f"認証情報が未設定: {', '.join(missing)}（scripts/asc.env.example を asc.env にコピーして記入）")


def token():
    kid = os.environ["ASC_KEY_ID"]
    path = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{kid}.p8")
    if not os.path.exists(path):
        sys.exit(f"API キーが見つかりません: {path}")
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200,
                       "aud": "appstoreconnect-v1"},
                      open(path).read(), algorithm="ES256", headers={"kid": kid})


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method, headers={
        "Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            text = r.read().decode()
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path} -> HTTP {e.code}\n{e.read().decode()[:2000]}")
    return json.loads(text) if text else {}


# MARK: - 参照

def app_id():
    return os.environ["ASC_APP_ID"]


def versions():
    return call("GET", f"/apps/{app_id()}/appStoreVersions?limit=10"
                       "&fields[appStoreVersions]=versionString,appVersionState,releaseType")["data"]


def state_of(v):
    return v["attributes"]["appVersionState"]


def builds(limit=20):
    return call("GET", f"/builds?filter[app]={app_id()}&sort=-uploadedDate&limit={limit}"
                       "&fields[builds]=version,processingState,uploadedDate,expired")["data"]


def find_build(number):
    return next((b for b in builds() if b["attributes"]["version"] == str(number)), None)


def pbx_version():
    s = open(PBX).read()
    v = re.search(r"MARKETING_VERSION = ([0-9.]+);", s).group(1)
    b = re.search(r"CURRENT_PROJECT_VERSION = ([0-9]+);", s).group(1)
    return v, b


# MARK: - コマンド

def cmd_status(_):
    v, b = pbx_version()
    print(f"pbxproj: v{v} (build {b})")
    print("== App Store versions ==")
    for ver in versions():
        a = ver["attributes"]
        print(f"  {a['versionString']:8} {state_of(ver):28} release={a['releaseType']}")
    print("== Builds (newest first) ==")
    for bd in builds(8):
        a = bd["attributes"]
        pv = call("GET", f"/builds/{bd['id']}/preReleaseVersion?fields[preReleaseVersions]=version")["data"]
        train = pv["attributes"]["version"] if pv else "?"
        print(f"  build {a['version']:4} train {train:8} {a['processingState']:10} uploaded={a['uploadedDate'][:10]}")


def wait_for_build(number, minutes):
    deadline = time.time() + minutes * 60
    while True:
        b = find_build(number)
        st = b["attributes"]["processingState"] if b else "NOT_FOUND"
        if st == "VALID":
            return b
        if st in ("FAILED", "INVALID"):
            sys.exit(f"build {number} は処理に失敗しました: {st}")
        if time.time() > deadline:
            sys.exit(f"build {number} is still {st}（{minutes}分待っても処理が終わりません）")
        print(f"  build {number}: {st} … 60秒待機")
        time.sleep(60)


def cmd_submit(a):
    pv, pb = pbx_version()
    version, build = a.version or pv, a.build or pb
    notes = open(a.notes, encoding="utf-8").read().strip()
    if not notes:
        sys.exit("新機能テキストが空です")
    print(f"==> 提出: v{version} (build {build})  release={a.release}")

    print("==> 1/4 ビルドの処理状態")
    b = wait_for_build(build, a.wait_minutes)
    print(f"  build {build}: VALID")

    print("==> 2/4 バージョン")
    ver = next((v for v in versions() if v["attributes"]["versionString"] == version), None)
    if ver is None:
        # 新規作成。前バージョンの ja ローカライズ（説明文等）は ASC 側で複製される。
        ver = call("POST", "/appStoreVersions", {"data": {
            "type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": version, "releaseType": a.release},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id()}}}}})["data"]
        print(f"  v{version} を作成")
    else:
        st = state_of(ver)
        if st not in EDITABLE:
            sys.exit(f"version {version} is {st}: 編集/提出できる状態ではありません")
        call("PATCH", f"/appStoreVersions/{ver['id']}", {"data": {
            "type": "appStoreVersions", "id": ver["id"], "attributes": {"releaseType": a.release}}})
        print(f"  v{version} は既存（{st}）")
    vid = ver["id"]

    print("==> 3/4 新機能テキスト・ビルド紐付け")
    locs = call("GET", f"/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]
    ja = next((l for l in locs if l["attributes"]["locale"] == "ja"), None)
    if ja is None:
        sys.exit("ja ローカライズがありません（ASC で日本語のストア情報を作成してから再実行）")
    call("PATCH", f"/appStoreVersionLocalizations/{ja['id']}", {"data": {
        "type": "appStoreVersionLocalizations", "id": ja["id"], "attributes": {"whatsNew": notes}}})
    call("PATCH", f"/appStoreVersions/{vid}/relationships/build",
         {"data": {"type": "builds", "id": b["id"]}})
    print(f"  whatsNew 設定・build {build} 紐付け")

    if a.dry_run:
        print("==> 4/4 --dry-run のため提出しません（ASC 上は「提出準備完了」のまま）")
        return
    print("==> 4/4 審査へ提出")
    sub = call("POST", "/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id()}}}}})["data"]
    call("POST", "/reviewSubmissionItems", {"data": {
        "type": "reviewSubmissionItems",
        "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    call("PATCH", f"/reviewSubmissions/{sub['id']}", {"data": {
        "type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}})
    print(f"\n✅ v{version} (build {build}) を審査に提出しました（{a.release}）。")
    print("   審査は通常1〜3日。結果は ASC の App Review と連絡先メールに届きます。")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = p.add_subparsers(dest="cmd", required=True)
    sp.add_parser("status", help="バージョン/ビルドの状態").set_defaults(fn=cmd_status)
    q = sp.add_parser("submit", help="審査に提出")
    q.add_argument("--notes", required=True, help="「このバージョンの新機能」テキストファイル (ja)")
    q.add_argument("--version", help="既定: pbxproj の MARKETING_VERSION")
    q.add_argument("--build", help="既定: pbxproj の CURRENT_PROJECT_VERSION")
    q.add_argument("--release", default="AFTER_APPROVAL", choices=["AFTER_APPROVAL", "MANUAL"],
                   help="承認後に自動公開（既定）/ 手動公開")
    q.add_argument("--wait-minutes", type=int, default=30, help="ビルド処理待ちの上限（分）")
    q.add_argument("--dry-run", action="store_true", help="提出せず手前まで")
    q.set_defaults(fn=cmd_submit)
    a = p.parse_args()
    load_env()
    a.fn(a)


if __name__ == "__main__":
    main()
