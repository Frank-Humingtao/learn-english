#!/usr/bin/env python3
"""Build the read-only reference lexicon shared by the App and GitHub Actions.

Merges:
  * BNC/COCA word family lists (Nation, via Laurence Anthony's Word Family Finder,
    basewords 1.3.0): families, 1000-family levels, member frequencies. Downloaded at
    build time only; never committed.
  * ECDICT (MIT): phonetic, English definition, Chinese translation, POS, exam tags,
    inflection data; plus its lemma.en.txt form -> lemma map.
  * Wiktextract English (kaikki.org, CC BY-SA 4.0 / GFDL): one example sentence and a
    pronunciation audio URL per lemma. Streamed; only the selected fields are kept.

BNC/COCA and ECDICT are pinned (ECDICT to a commit; both by sha256, checked on --download), so
every machine — the developer's App bundle and the GitHub Actions run — builds the same lexicon.
The version hashes everything except the Wiktextract-derived columns (phonetic, example, audio):
Wiktextract is unpinned and Actions skips it, and none of it affects the Learner Profile.

Output directory (load with `Lexicon.load(directory:)` in EnglishCore):
  meta.json          version (hash of the profile-relevant content), sources, counts
  words.tsv          one row per lemma, sorted by rank
  forms.tsv          inflected form -> lemma
  supplementary.txt  proper names / marginal words / compounds / acronyms (known for Coverage)

TSV fields escape backslash, tab and newline as \\\\, \\t, \\n.

Usage:
  python3 -I tools/lexicon-build/build_lexicon.py --download            # full build
  python3 -I tools/lexicon-build/build_lexicon.py --wiktextract-limit 200000 --sample-every 50 --out X
  python3 -I tools/lexicon-build/build_lexicon.py --restamp DIR       # recompute DIR's meta version
"""
import argparse
import csv
import hashlib
import io
import json
import os
import re
import sys
import time
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CACHE = os.path.join(HERE, "cache")
DEFAULT_OUT = os.path.join(HERE, "out")

BASEWORDS_ZIP = "basewords_130.zip"
ECDICT_FILE = "ecdict.csv"
LEMMA_FILE = "lemma.en.txt"
KAIKKI_FILE = "kaikki-English.jsonl"

ECDICT_COMMIT = "39cfb9672c0906b63569e0453c2e6abfb9ab182a"
SOURCES = {
    BASEWORDS_ZIP: "https://laurenceanthony.net/software/wordfamilyfinder/downloads/basewords_130.zip",
    ECDICT_FILE: "https://raw.githubusercontent.com/skywind3000/ECDICT/%s/ecdict.csv" % ECDICT_COMMIT,
    LEMMA_FILE: "https://raw.githubusercontent.com/skywind3000/ECDICT/%s/lemma.en.txt" % ECDICT_COMMIT,
    KAIKKI_FILE: "https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl",
}
# Profile-relevant sources must be byte-identical everywhere. Wiktextract is not pinned (kaikki.org
# only serves the latest dump) and is excluded from the version instead.
SHA256 = {
    BASEWORDS_ZIP: "156a563114bbdef2a9b526e50309baa93bac0809f28643a11830126cdf0a08ee",
    ECDICT_FILE: "d1ecbdf9ee2b920afb6f430ca6b6bb9f559588cf0dff86e04bd255f9390843cc",
    LEMMA_FILE: "e255b097404e3e0052060e2ddf6e15a1414f577071d63d51d2ca0ce9dacee0fc",
}

MAX_LEVEL = 25
SUPPLEMENTARY_LISTS = range(31, 36)
MAX_EXAMPLE_CHARS = 160
CONTRACTION_FRAGMENTS = {"ain", "ll", "ve", "em", "nt"}
WORD_RE = re.compile(r'"word": "((?:[^"\\]|\\.)*)", "lang": "([^"]*)", "lang_code": "([^"]*)"')

COLUMNS = ["lemma", "rank", "family", "family_rank", "level", "freq", "phonetic", "pos", "tags",
           "definition", "translation", "example", "audio"]
# Filled (or, for phonetic, completed) from Wiktextract: not part of the version.
UNVERSIONED_COLUMNS = {"phonetic", "example", "audio"}


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def verify_source(cache, name):
    """Raises if a pinned source in the cache is not the pinned file."""
    want = SHA256.get(name)
    if want is None:
        return
    got = sha256_of(os.path.join(cache, name))
    if got != want:
        raise SystemExit(f"{name}: sha256 {got} is not the pinned {want}; delete it from the cache "
                         "and download again (or update the pin deliberately)")


def download_sources(cache):
    os.makedirs(cache, exist_ok=True)
    for name, url in SOURCES.items():
        path = os.path.join(cache, name)
        if os.path.exists(path):
            verify_source(cache, name)
            continue
        tmp = path + ".part"
        # Some hosts reject urllib's default User-Agent (HTTP 406); send a generic one.
        req = urllib.request.Request(url, headers={"User-Agent": "lexicon-build/1.0", "Accept": "*/*"})
        for attempt in range(1, 4):
            log(f"downloading {url} (attempt {attempt})")
            try:
                with urllib.request.urlopen(req, timeout=120) as r, open(tmp, "wb") as f:
                    while True:
                        chunk = r.read(1 << 20)
                        if not chunk:
                            break
                        f.write(chunk)
                break
            except OSError as e:  # URLError, SSL and socket errors
                log(f"  failed: {e}")
                if attempt == 3:
                    raise
                time.sleep(5 * attempt)
        os.replace(tmp, path)
        verify_source(cache, name)


def escape(s):
    return s.replace("\\", "\\\\").replace("\t", "\\t").replace("\r", "").replace("\n", "\\n")


# --- inputs -------------------------------------------------------------------

def read_families(cache):
    """Returns (families, supplementary). families: list of (level, headword, [(form, freq)]),
    headword first."""
    families, supplementary = [], set()
    with zipfile.ZipFile(os.path.join(cache, BASEWORDS_ZIP)) as z:
        names = {os.path.basename(n): n for n in z.namelist()}
        for list_no in list(range(1, MAX_LEVEL + 1)) + list(SUPPLEMENTARY_LISTS):
            name = names.get(f"basewrd{list_no}.txt")
            if name is None:
                continue
            text = z.read(name).decode("utf-8", errors="replace")
            current = None
            for raw in text.splitlines():
                if not raw.strip():
                    continue
                parts = raw.strip().split()
                form = parts[0].lower()
                freq = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 0
                if list_no in SUPPLEMENTARY_LISTS:
                    supplementary.add(form)
                    continue
                if raw[0] in " \t":
                    if current is not None:
                        current[2].append((form, freq))
                else:
                    current = (list_no, form, [(form, freq)])
                    families.append(current)
    return families, supplementary


def read_lemma_map(cache):
    """form -> set of lemmas, from ECDICT's lemma.en.txt."""
    form_to_lemmas, lemma_forms = {}, {}
    with open(os.path.join(cache, LEMMA_FILE), encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith(";") or "->" not in line:
                continue
            head, forms = line.split("->", 1)
            lemma = head.split("/")[0].strip().lower()
            fs = [x.strip().lower() for x in forms.split(",") if x.strip()]
            lemma_forms.setdefault(lemma, []).extend(fs)
            for x in fs:
                form_to_lemmas.setdefault(x, set()).add(lemma)
    return form_to_lemmas, lemma_forms


def read_ecdict(cache, wanted):
    rows = {}
    with open(os.path.join(cache, ECDICT_FILE), encoding="utf-8", errors="replace", newline="") as f:
        for row in csv.DictReader(f):
            w = row["word"]
            key = w.lower()
            if key not in wanted:
                continue
            # Prefer the exact lower-case spelling over capitalized variants.
            if key in rows and w != key:
                continue
            rows[key] = row
    return rows


def ecdict_inflections(row):
    """Inflected forms listed in ECDICT's exchange field (not the lemma pointer `0:`)."""
    out = []
    for part in (row.get("exchange") or "").split("/"):
        if ":" in part:
            kind, form = part.split(":", 1)
            if kind in ("p", "d", "i", "3", "s", "r", "t") and form:
                out.append(form.lower())
    return out


def read_wiktextract(cache, wanted, limit=None):
    """lemma -> {"example", "audio", "ipa"} for lemmas in `wanted` (first English entry wins
    per field)."""
    path = os.path.join(cache, KAIKKI_FILE)
    found = {}
    if not os.path.exists(path):
        log("wiktextract file missing; examples and audio will be empty")
        return found
    with open(path, encoding="utf-8", errors="replace") as f:
        for n, line in enumerate(f):
            if limit is not None and n >= limit:
                log(f"wiktextract: stopped after {limit} lines (capped)")
                break
            m = WORD_RE.search(line)
            if m is None:
                continue
            word = json.loads('"' + m.group(1) + '"').lower()
            if word not in wanted or m.group(3) != "en":
                continue
            entry = json.loads(line)
            if entry.get("lang_code") != "en":
                continue
            info = found.setdefault(word, {"example": "", "audio": "", "ipa": ""})
            if not info["example"]:
                for sense in entry.get("senses", []):
                    for ex in sense.get("examples", []):
                        text = (ex.get("text") or "").strip()
                        if ex.get("type", "example") == "example" and 0 < len(text) <= MAX_EXAMPLE_CHARS:
                            info["example"] = text
                            break
                    if info["example"]:
                        break
            for s in entry.get("sounds", []):
                if not info["audio"] and s.get("mp3_url"):
                    info["audio"] = s["mp3_url"]
                if not info["ipa"] and s.get("ipa"):
                    info["ipa"] = s["ipa"]
    return found


# --- version ------------------------------------------------------------------

def content_version(words_text, forms_text, supp_text):
    """`lex-` + 12 hex digits of SHA-256 over words.tsv without the Wiktextract-derived columns,
    forms.tsv and supplementary.txt."""
    lines = words_text.split("\n")
    header = lines[0].split("\t")
    keep = [i for i, c in enumerate(header) if c not in UNVERSIONED_COLUMNS]
    digest = hashlib.sha256()
    for line in lines:
        if line:
            cells = line.split("\t")
            digest.update(("\t".join(cells[i] for i in keep if i < len(cells)) + "\n").encode("utf-8"))
    digest.update(forms_text.encode("utf-8"))
    digest.update(supp_text.encode("utf-8"))
    return "lex-" + digest.hexdigest()[:12]


def version_of(directory):
    texts = []
    for name in ("words.tsv", "forms.tsv", "supplementary.txt"):
        with open(os.path.join(directory, name), encoding="utf-8", newline="") as f:
            texts.append(f.read())
    return content_version(*texts)


def restamp(directory):
    """Rewrites meta.json's version from the directory's content (e.g. the committed fixture)."""
    path = os.path.join(directory, "meta.json")
    with open(path, encoding="utf-8") as f:
        meta = json.load(f)
    meta["version"] = version_of(directory)
    meta["sources"] = SOURCE_NOTES
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(meta, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    return meta["version"]


SOURCE_NOTES = {
    "bnc_coca": "BNC/COCA word family lists (Nation), basewords 1.3.0; levels 1-25; lists 31-35 as supplementary; "
                "sha256 " + SHA256[BASEWORDS_ZIP],
    "ecdict": "ECDICT (skywind3000), MIT; commit " + ECDICT_COMMIT,
    "wiktextract": "Wiktextract English via kaikki.org; examples and audio URLs, CC BY-SA 4.0 / GFDL; "
                   "not part of the version",
}


# --- build --------------------------------------------------------------------

def select_lemmas(families, form_to_lemmas, ecdict):
    """For each family, split members into lemmas and inflections.
    Returns list of families as (level, headword, family_freq, [(lemma, freq, [inflected forms])])."""
    out = []
    for level, head, members in families:
        member_set = {f for f, _ in members}
        owner = {}
        for form, _ in members:
            if form == head:
                continue
            parents = {l for l in form_to_lemmas.get(form, ()) if l in member_set and l != form}
            row = ecdict.get(form)
            if row:
                for part in (row.get("exchange") or "").split("/"):
                    if part.startswith("0:") and part[2:].lower() in member_set and part[2:].lower() != form:
                        parents.add(part[2:].lower())
            if parents:
                owner[form] = head if head in parents else sorted(parents)[0]
        # Resolve chains (a form whose parent is itself an inflection).
        def root(f):
            seen = set()
            while f in owner and f not in seen:
                seen.add(f)
                f = owner[f]
            return f
        lemmas = {}
        for form, freq in members:
            r = root(form)
            entry = lemmas.setdefault(r, [0, []])
            entry[0] += freq
            if r != form:
                entry[1].append(form)
        # Keep the headword and lemmas ECDICT knows (drops typos/oddities in member lists),
        # minus contraction fragments the family lists carry (s, wasn, isn, aren, ain...).
        def fragment(l):
            return len(l) == 1 or l in CONTRACTION_FRAGMENTS or (l.endswith("n") and l[:-1] in member_set)
        kept = [(l, fq, sorted(infl)) for l, (fq, infl) in lemmas.items()
                if l == head or (l in ecdict and not fragment(l))]
        family_freq = sum(fq for _, fq in members)
        out.append((level, head, family_freq, kept))
    return out


def build(cache=DEFAULT_CACHE, out=DEFAULT_OUT, download=False, wiktextract_limit=None, sample_every=1):
    if download:
        download_sources(cache)
    families, supplementary = read_families(cache)
    log(f"families: {len(families)}, supplementary words: {len(supplementary)}")
    form_to_lemmas, lemma_forms = read_lemma_map(cache)
    all_forms = {f for _, _, ms in families for f, _ in ms}
    ecdict = read_ecdict(cache, all_forms | set(lemma_forms))
    fams = select_lemmas(families, form_to_lemmas, ecdict)

    # Family rank: level, then family frequency, then headword. Lemma rank: level, then
    # lemma frequency, then spelling.
    fams.sort(key=lambda f: (f[0], -f[2], f[1]))
    rows, seen = [], set()
    for family_rank, (level, head, _, lemmas) in enumerate(fams, start=1):
        for lemma, freq, infl in lemmas:
            if lemma in seen:  # a lemma listed in two families keeps the first
                continue
            seen.add(lemma)
            rows.append({"lemma": lemma, "family": head, "family_rank": family_rank, "level": level,
                         "freq": freq, "inflections": infl})
    rows.sort(key=lambda r: (r["level"], -r["freq"], r["lemma"]))
    for rank, r in enumerate(rows, start=1):
        r["rank"] = rank

    if sample_every > 1:
        # Fixture mode: a thin slice, so no BNC/COCA list is reproduced wholesale.
        rows = [r for r in rows if (r["family_rank"] - 1) % sample_every == 0]
        supplementary = set(sorted(supplementary)[::sample_every])

    lemma_set = {r["lemma"] for r in rows}
    wik = read_wiktextract(cache, lemma_set, wiktextract_limit)

    # Forms: family inflections first, then lemma.en.txt and ECDICT exchange forms.
    # A form never maps away from a lemma; on conflict the more frequent lemma wins.
    forms = {}
    for r in rows:  # rank order = frequency order
        candidates = list(r["inflections"]) + lemma_forms.get(r["lemma"], [])
        if r["lemma"] in ecdict:
            candidates += ecdict_inflections(ecdict[r["lemma"]])
        for f in candidates:
            if f != r["lemma"] and f not in lemma_set and f not in forms and re.fullmatch(r"[a-z][a-z'\-]*", f):
                forms[f] = r["lemma"]

    os.makedirs(out, exist_ok=True)
    words_buf = io.StringIO()
    words_buf.write("\t".join(COLUMNS) + "\n")
    for r in rows:
        e = ecdict.get(r["lemma"], {})
        w = wik.get(r["lemma"], {})
        values = {
            "lemma": r["lemma"], "rank": str(r["rank"]), "family": r["family"],
            "family_rank": str(r["family_rank"]), "level": str(r["level"]), "freq": str(r["freq"]),
            "phonetic": e.get("phonetic") or w.get("ipa", "").strip("/"),
            "pos": e.get("pos") or "", "tags": e.get("tag") or "",
            "definition": (e.get("definition") or "").replace("\\n", "\n"),
            "translation": (e.get("translation") or "").replace("\\n", "\n"),
            "example": w.get("example", ""), "audio": w.get("audio", ""),
        }
        words_buf.write("\t".join(escape(values[c]) for c in COLUMNS) + "\n")
    forms_buf = io.StringIO()
    forms_buf.write("form\tlemma\n")
    for f in sorted(forms):
        forms_buf.write(f"{escape(f)}\t{escape(forms[f])}\n")
    supp_text = "".join(f"{w}\n" for w in sorted(supplementary))

    meta = {
        "schema": 1,
        "version": content_version(words_buf.getvalue(), forms_buf.getvalue(), supp_text),
        "counts": {"lemmas": len(rows), "families": len({r["family"] for r in rows}), "forms": len(forms),
                   "supplementary": len(supplementary),
                   "with_example": sum(1 for r in rows if wik.get(r["lemma"], {}).get("example")),
                   "with_audio": sum(1 for r in rows if wik.get(r["lemma"], {}).get("audio"))},
        "build": {"sample_every": sample_every, "wiktextract_limit": wiktextract_limit},
        "sources": SOURCE_NOTES,
    }
    for name, text in (("words.tsv", words_buf.getvalue()), ("forms.tsv", forms_buf.getvalue()),
                       ("supplementary.txt", supp_text),
                       ("meta.json", json.dumps(meta, ensure_ascii=False, indent=2, sort_keys=True) + "\n")):
        with open(os.path.join(out, name), "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    log(f"wrote {out}: {meta['version']} {json.dumps(meta['counts'])}")
    return meta


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--cache", default=DEFAULT_CACHE, help="raw downloads (gitignored)")
    p.add_argument("--out", default=DEFAULT_OUT)
    p.add_argument("--download", action="store_true", help="download missing sources into --cache")
    p.add_argument("--wiktextract-limit", type=int, default=None, help="read at most N Wiktextract lines")
    p.add_argument("--sample-every", type=int, default=1, help="keep every Nth family (test fixtures)")
    p.add_argument("--restamp", metavar="DIR", help="only recompute DIR/meta.json's version and exit")
    a = p.parse_args(argv)
    if a.restamp:
        print(restamp(a.restamp))
        return
    build(cache=a.cache, out=a.out, download=a.download, wiktextract_limit=a.wiktextract_limit,
          sample_every=a.sample_every)


if __name__ == "__main__":
    main()
