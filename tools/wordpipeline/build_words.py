#!/usr/bin/env python3
"""
Wordlet kelime pipeline'ı — adım 1: yeniden seviyelendirme + zenginleştirme.

Shared/words.json içindeki her kelimeye şunları ekler (yerinde, tekrar çalıştırılabilir):
  level     CEFR seviyesi (A1-B2). Önce CEFR-J, yoksa kelime sıklığına göre tahmin.
  pos       Kelime türü (noun / verb / adjective / adverb ...)
  freqRank  wordfreq'e göre İngilizce sıklık sırası (1 = en yaygın)
  levelSource  "cefrj" veya "freq" (sıklıktan tahmin edildi, elle kontrol edilmeli)

Ayrıca reports/ altına şu raporları yazar:
  summary.md               Seviye dağılımı ve eski/yeni karşılaştırması
  hard_examples.csv        Örnek cümlesi kelimenin seviyesinin üstünde kalanlar
  missing_core_words.csv   CEFR-J A1/A2 içerik kelimeleri olup veride olmayanlar
  freq_guessed.csv         CEFR-J'de bulunmayıp sıklıktan seviye verilenler
  template_examples.csv    Şablondan üretilmiş anlamsız örnek cümleler ("... the concept of X.")
  suspect_translations.csv Türkçe karşılığın türü İngilizce kelimeyle uyuşmayanlar (elle bakılacak)

Ek alan: exampleIsTemplate = true → örnek cümle şablon, yeniden üretilmeli.

Kullanım:
  python3 -m venv .venv && .venv/bin/pip install -r tools/wordpipeline/requirements.txt
  .venv/bin/python tools/wordpipeline/build_words.py

Veri kaynağı: The CEFR-J Wordlist Version 1.5, compiled by Yukio Tono,
Tokyo University of Foreign Studies (http://www.cefr-j.org/download.html),
via Open Language Profiles. Ticari kullanım atıf şartıyla serbesttir.
"""

from __future__ import annotations

import collections
import csv
import json
import re
from pathlib import Path

from lemminflect import getAllLemmas
from wordfreq import top_n_list

ROOT = Path(__file__).resolve().parents[2]
WORDS_JSON = ROOT / "Shared" / "words.json"
CEFRJ_CSV = Path(__file__).parent / "data" / "cefrj-vocabulary-profile-1.5.csv"
REPORTS = Path(__file__).parent / "reports"

LEVELS = ["A1", "A2", "B1", "B2"]
LEVEL_INDEX = {lvl: i for i, lvl in enumerate(LEVELS)}
CONTENT_POS = {"noun", "verb", "adjective", "adverb"}

# Plan: CEFR-J'de olmayan kelimeler için sıklık aralığına göre kaba tahmin
FREQ_BANDS = [(800, "A1"), (1800, "A2"), (3500, "B1")]  # üstü B2

# Örnek cümlede, hedef kelime dışında en fazla bu kadar üst seviye kelimeye izin ver
MAX_HARD_TOKENS = 1

# Aynı cümle iskeleti bu kadar kelimede tekrarlanıyorsa şablon say. Eski şablonlar 300+ kez
# tekrarlanıyordu; "My arm hurts." gibi birkaç doğal tekrar şablon sayılmasın.
TEMPLATE_MIN_REPEATS = 10

# lemminflect POS etiketleri -> CEFR-J POS
UPOS_TO_CEFRJ = {"NOUN": "noun", "VERB": "verb", "ADJ": "adjective", "ADV": "adverb"}


# ---------------------------------------------------------------------------
# Kaynakları yükle
# ---------------------------------------------------------------------------

def load_cefrj() -> dict[str, list[tuple[str, str]]]:
    """headword (küçük harf) -> [(pos, level), ...]. "adviser/advisor" gibi varyantlar ayrı anahtar olur."""
    table: dict[str, list[tuple[str, str]]] = collections.defaultdict(list)
    with CEFRJ_CSV.open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            level = row["CEFR"].strip()
            if level not in LEVEL_INDEX:
                continue
            for variant in row["headword"].split("/"):
                key = variant.strip().lower()
                if key:
                    table[key].append((row["pos"].strip(), level))
    return table


def load_freq_rank(limit: int = 100_000) -> dict[str, int]:
    return {w: i + 1 for i, w in enumerate(top_n_list("en", limit))}


# ---------------------------------------------------------------------------
# Seviye ve tür belirleme
# ---------------------------------------------------------------------------

def looks_like_turkish_verb(turkish: str) -> bool:
    # "Davet Etmek", "Koşmak" -> fiil
    last = turkish.strip().lower().split()[-1] if turkish.strip() else ""
    return last.endswith(("mek", "mak"))


def pick_entry(entries: list[tuple[str, str]], turkish: str) -> tuple[str, str]:
    """Aynı kelimenin birden fazla türü varsa (light: isim/sıfat/fiil), Türkçe karşılığa göre seç."""
    if looks_like_turkish_verb(turkish):
        verbs = [e for e in entries if e[0] == "verb"]
        if verbs:
            return min(verbs, key=lambda e: LEVEL_INDEX[e[1]])
    non_verbs = [e for e in entries if e[0] != "verb"] or entries
    return min(non_verbs, key=lambda e: LEVEL_INDEX[e[1]])


def level_from_freq(rank: int | None) -> str:
    if rank is None:
        return "B2"
    for limit, level in FREQ_BANDS:
        if rank <= limit:
            return level
    return "B2"


def classify(word: dict, cefrj, freq_rank) -> dict:
    english = word["english"].strip()
    key = english.lower()
    rank = freq_rank.get(key)

    entries = cefrj.get(key)
    if entries:
        pos, level = pick_entry(entries, word.get("turkish", ""))
        source = "cefrj"
    else:
        # Çekimli hali verilmiş olabilir ("injured" -> "injure")
        pos, level, source = None, None, "freq"
        for upos, lemmas in getAllLemmas(key).items():
            for lemma in lemmas:
                if lemma in cefrj:
                    pos, level = pick_entry(cefrj[lemma], word.get("turkish", ""))
                    source = "cefrj"
                    break
            if level:
                break
        if not level:
            level = level_from_freq(rank)
            pos = "verb" if looks_like_turkish_verb(word.get("turkish", "")) else None

    return {"level": level, "pos": pos, "freqRank": rank, "levelSource": source}


# ---------------------------------------------------------------------------
# Örnek cümle zorluğu
# ---------------------------------------------------------------------------

TOKEN_RE = re.compile(r"[A-Za-z]+(?:'[a-z]+)?")


def token_level(token: str, cefrj, freq_rank) -> int | None:
    """Bir cümle kelimesinin en düşük olası seviyesi (index). Bilinmiyorsa sıklıktan tahmin."""
    t = token.lower()
    if "'" in t:  # don't, it's, I'm -> A1
        return 0
    candidates = {t}
    for lemmas in getAllLemmas(t).values():
        candidates.update(lemmas)
    known = [LEVEL_INDEX[lvl] for c in candidates for _, lvl in cefrj.get(c, [])]
    if known:
        return min(known)
    # Özel isimler ve sayılar cümlenin zorluğunu artırmaz
    if token[0].isupper():
        return None
    return LEVEL_INDEX[level_from_freq(freq_rank.get(t))]


def hard_tokens(sentence: str, target: str, level: str, cefrj, freq_rank) -> list[str]:
    target_forms = {target.lower()}
    for lemmas in getAllLemmas(target.lower()).values():
        target_forms.update(lemmas)

    limit = LEVEL_INDEX[level]
    hard = []
    for i, tok in enumerate(TOKEN_RE.findall(sentence)):
        low = tok.lower()
        lemmas = {low} | {l for ls in getAllLemmas(low).values() for l in ls}
        if lemmas & target_forms or low.startswith(target.lower()):
            continue
        # Cümle başındaki büyük harf özel isim değildir
        lvl = token_level(tok if i else tok.lower(), cefrj, freq_rank)
        if lvl is not None and lvl > limit:
            hard.append(tok)
    return hard


# ---------------------------------------------------------------------------
# Ana akış
# ---------------------------------------------------------------------------

def old_level_from_id(word_id: str) -> str:
    n = int(word_id) if word_id.isdigit() else 1
    return "A1" if n <= 500 else "A2" if n <= 1000 else "B1" if n <= 1500 else "B2"


def main() -> None:
    cefrj = load_cefrj()
    freq_rank = load_freq_rank()
    words = json.loads(WORDS_JSON.read_text(encoding="utf-8"))

    REPORTS.mkdir(parents=True, exist_ok=True)

    # Aynı iskelet çok sayıda kelimede tekrar ediyorsa cümle şablondan üretilmiştir
    def skeleton(w):
        return re.sub(re.escape(w["english"].strip()), "<W>", w.get("example", ""), flags=re.I)
    skeleton_counts = collections.Counter(skeleton(w) for w in words)
    template_rows, suspect_rows = [], []
    moved = collections.Counter()
    hard_rows, guessed_rows = [], []

    for w in words:
        info = classify(w, cefrj, freq_rank)
        moved[(old_level_from_id(w["id"]), info["level"])] += 1

        w["level"] = info["level"]
        w["levelSource"] = info["levelSource"]
        if info["pos"]:
            w["pos"] = info["pos"]
        else:
            w.pop("pos", None)
        if info["freqRank"]:
            w["freqRank"] = info["freqRank"]
        else:
            w.pop("freqRank", None)

        if skeleton_counts[skeleton(w)] >= TEMPLATE_MIN_REPEATS:
            w["exampleIsTemplate"] = True
            template_rows.append([w["id"], w["english"], info["level"], w.get("example", "")])
        else:
            w.pop("exampleIsTemplate", None)

        if looks_like_turkish_verb(w.get("turkish", "")) and info["pos"] not in ("verb", None):
            suspect_rows.append([w["id"], w["english"], w["turkish"], info["pos"], "TR fiil, EN fiil değil"])

        if info["levelSource"] == "freq":
            guessed_rows.append([w["id"], w["english"], w["turkish"], info["level"], info["freqRank"] or ""])

        if w.get("exampleIsTemplate"):
            continue  # şablon cümleler zaten yeniden üretilecek
        hard = hard_tokens(w.get("example", ""), w["english"], info["level"], cefrj, freq_rank)
        if len(hard) > MAX_HARD_TOKENS:
            hard_rows.append([w["id"], w["english"], info["level"], " ".join(hard), w.get("example", "")])

    WORDS_JSON.write_text(json.dumps(words, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # --- Eksik temel kelimeler (A1/A2 içerik kelimeleri) ---
    have = {w["english"].strip().lower() for w in words}
    missing = []
    seen = set()
    with CEFRJ_CSV.open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["CEFR"] not in ("A1", "A2") or row["pos"] not in CONTENT_POS:
                continue
            variants = [v.strip().lower() for v in row["headword"].split("/")]
            head = variants[0]
            if any(v in have for v in variants) or (head, row["pos"]) in seen:
                continue
            seen.add((head, row["pos"]))
            missing.append([head, row["pos"], row["CEFR"], freq_rank.get(head, "")])
    missing.sort(key=lambda r: (r[2], r[3] if r[3] != "" else 10**9))

    def write_csv(name, header, rows):
        with (REPORTS / name).open("w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(header)
            writer.writerows(rows)

    write_csv("hard_examples.csv", ["id", "english", "level", "hard_tokens", "example"], hard_rows)
    write_csv("missing_core_words.csv", ["headword", "pos", "cefr", "freq_rank"], missing)
    write_csv("template_examples.csv", ["id", "english", "level", "example"], template_rows)
    write_csv("suspect_translations.csv", ["id", "english", "turkish", "pos", "reason"], suspect_rows)
    write_csv("freq_guessed.csv", ["id", "english", "turkish", "level", "freq_rank"], guessed_rows)

    # --- Özet ---
    new_counts = collections.Counter(w["level"] for w in words)
    sources = collections.Counter(w["levelSource"] for w in words)
    lines = [
        "# Kelime pipeline özeti",
        "",
        f"Toplam kelime: {len(words)}",
        f"Seviye kaynağı: CEFR-J {sources['cefrj']}, sıklıktan tahmin {sources['freq']}",
        "",
        "## Yeni seviye dağılımı",
        "",
        "| Seviye | Kelime |",
        "|---|---|",
        *[f"| {lvl} | {new_counts[lvl]} |" for lvl in LEVELS],
        "",
        "## Eski (ID'ye göre) → yeni seviye",
        "",
        "| Eski \\ Yeni | " + " | ".join(LEVELS) + " |",
        "|---|" + "---|" * len(LEVELS),
        *[f"| {old} | " + " | ".join(str(moved[(old, new)]) for new in LEVELS) + " |" for old in LEVELS],
        "",
        f"Şablondan üretilmiş örnek cümle: {len(template_rows)} (template_examples.csv) — yeniden üretilmeli",
        f"Seviyesinin üstünde örnek cümlesi olan kelime (şablonlar hariç): {len(hard_rows)} (hard_examples.csv)",
        f"Şüpheli çeviri: {len(suspect_rows)} (suspect_translations.csv)",
        f"Veride olmayan CEFR-J A1/A2 içerik kelimesi: {len(missing)} (missing_core_words.csv)",
        "",
        "Kaynak: The CEFR-J Wordlist Version 1.5, Yukio Tono, Tokyo University of Foreign Studies.",
    ]
    (REPORTS / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
