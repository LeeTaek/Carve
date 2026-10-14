"""영어 본문 리소스(KJV · BSB)를 앱 파서(Domain `BibleTextLine` · `BibleChapterTextParser`)와 같은 규칙으로 다시 읽어 검사한다.

본문 출처 · 변환 규칙은 같은 폴더 `bible_en_convert.py` 맨 위 주석에 있다. 요지:
- KJV: GitHub `christislord12/kjv-txt-files` 커밋 `99a395de`, BSB: `bereanbible.com/bsb_usfm.zip`(CC0) 을 스크립트로만 바꾼다.
- 형식: 한 줄 = `장:절 [<소제목>] 본문`, 줄 구분 CR, 파일 끝 CR 없음, UTF-8, 소제목 여럿은 `<…>` 안 LF.
- 파일 이름 `<번역본>-<BibleTitle.rawValue>`, 번역본에 없는 절은 줄이 없다.

검사하는 것: BOM · 파일 끝 CR · 참조 없는 줄 · 소제목 안 CR · 본문의 `<` `>` LF · 빈 본문 · 양끝 공백 · 겹친 공백 · 한 장 안 절 중복,
그리고 권마다 장 집합이 개역개정 같은 권과 같은지. 문제가 하나라도 있으면 종료 코드 1 이다.

쓰는 법 (저장소 루트에서, 인자 없이 부르면 저장소 사본을 본다)
    python3 scripts/bibletext/validate_bibletext.py [--text-dir <KJV/ · BSB/ 가 든 폴더>] [--nkrv <개역개정 폴더>]
"""
import argparse
import collections
import os
import re

# 이 스크립트 기준 저장소의 본문 리소스 폴더(scripts/bibletext → 저장소 루트).
REPO_TEXT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'Shared', 'Resources', 'Resources', 'BibleText')


def chapters_of(path, enc):
    """본문 파일에서 줄 맨 앞 `장:` 의 장 번호 집합을 읽는다."""
    raw = open(path, 'rb').read().decode(enc)
    chs = set()
    for line in raw.split('\r'):
        m = re.match(r'^\s*(\d+):', line)
        if m: chs.add(int(m.group(1)))
    return chs


def validate(text_dir, nkrv_dir):
    """`text_dir/{KJV,BSB}` 를 검사해 (통계, 문제 목록) 을 돌려준다."""
    problems = []; stats = collections.Counter()
    for label in ('KJV', 'BSB'):
        for f in sorted(os.listdir(os.path.join(text_dir, label))):
            raw = open(os.path.join(text_dir, label, f), 'rb').read()
            if raw.startswith(b'\xef\xbb\xbf'): problems.append((f, 'BOM'))
            text = raw.decode('utf-8')
            if text.endswith('\r'): problems.append((f, 'trailing CR'))
            seen = collections.defaultdict(set)
            for i, line in enumerate(text.split('\r')):
                m = re.match(r'^(\d+):(\d+) (.*)$', line, re.S)
                if not m: problems.append((f, i, 'no ref', line[:40])); continue
                c, v, rest = int(m.group(1)), int(m.group(2)), m.group(3)
                if rest.startswith('<'):
                    end = rest.index('>'); heading, body = rest[1:end], rest[end + 1:].strip(); stats[label + ' 소제목'] += 1
                    if '\r' in heading: problems.append((f, c, v, 'CR in heading'))
                else: body = rest
                if '<' in body or '>' in body or '\n' in body: problems.append((f, c, v, 'stray', body[:40]))
                if not body or body != body.strip() or '  ' in body: problems.append((f, c, v, 'space/empty'))
                if v in seen[c]: problems.append((f, c, v, 'dup'))
                seen[c].add(v); stats[label + ' 절'] += 1
            nk = chapters_of(os.path.join(nkrv_dir, f.split('-', 1)[1]), 'cp949')
            if set(seen) != nk: problems.append((f, 'chapters', len(seen), len(nk)))
            stats[label + ' 장'] += len(seen); stats[label + ' 권'] += 1
    return stats, problems


def main():
    parser = argparse.ArgumentParser(description='영어 본문 리소스를 앱 파서 규칙으로 검사한다.')
    parser.add_argument('--text-dir', default=REPO_TEXT_DIR, help='KJV/ · BSB/ 가 든 폴더(기본: 저장소 Shared/Resources/Resources/BibleText)')
    parser.add_argument('--nkrv', default=None, help='개역개정 본문 폴더(기본: <text-dir>/NKRV)')
    args = parser.parse_args()
    text_dir = os.path.normpath(args.text_dir)
    nkrv_dir = os.path.normpath(args.nkrv or os.path.join(text_dir, 'NKRV'))

    stats, problems = validate(text_dir, nkrv_dir)
    print(dict(stats)); print('문제', len(problems), problems[:10])
    return 1 if problems else 0


if __name__ == '__main__':
    raise SystemExit(main())
