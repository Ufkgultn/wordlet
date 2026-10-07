#!/usr/bin/env python3
"""
Wordlet kelime pipeline'ı — adım 3: anlam incelemesi (Antigravity CLI `agy` ile).

Doğrulayıcı (generate_content.problems) zor kelimeleri ve hedef kelimenin varlığını kontrol eder,
ama ANLAMI kontrol edemez: "Draw = Çizmek" kartında "The game ended in a draw." cümlesi gibi.
Bu script seviyedeki her kelimeyi bir modele inceletir:
  - Türkçe karşılık, kelimenin bu seviyedeki en yaygın anlamı mı?
  - Örnek cümle kelimeyi AYNI anlam ve türde mi kullanıyor? Tam, doğal ve seviyeye uygun mu?
  - Cümlenin Türkçesi doğru mu?
Sorunlu kartlar düzeltilir; düzeltmeler yine problems() doğrulamasından geçer.

agy sadece metin üretir: boş bir geçici klasörde, araç izni olmadan, JSON şemasıyla çalışır.
Dosyaya yazma ve doğrulama bu script tarafından yapılır.

Kullanım:
  .venv/bin/python tools/wordpipeline/review_agy.py --level A1 --limit 40 --dry-run   # deneme
  .venv/bin/python tools/wordpipeline/review_agy.py --level A1                       # uygula
Çıktı: reports/review_<seviye>.csv (her değişiklik ve gerekçesi). Yarıda kalırsa tekrar
çalıştırın: sonuçlar cache/review_<seviye>.jsonl içinde tutulur.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import build_words as bw  # noqa: E402
import generate_content as gc  # noqa: E402

DEFAULT_MODEL = "gemini-3.1-pro-low"

SCHEMA = {
    "type": "object",
    "properties": {
        "items": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "key": {"type": "string"},
                    "ok": {"type": "boolean"},
                    "turkish": {"type": "string"},
                    "example": {"type": "string"},
                    "exampleTurkish": {"type": "string"},
                    "note": {"type": "string"},
                },
                "required": ["key", "ok", "turkish", "example", "exampleTurkish", "note"],
            },
        }
    },
    "required": ["items"],
}

RULES = """You are reviewing vocabulary flashcards for an app that teaches English to native Turkish speakers.
Each card: English word, part of speech (pos), CEFR level, Turkish meaning, an English example sentence and its Turkish translation.

Check each card:
1. "turkish" must be the most common meaning of the word for that pos AT THIS LEVEL (e.g. A1 "draw" = "Çizmek",
   not "Beraberlik"). Short (1-3 words), dictionary form (verbs end in -mek/-mak), first letter capitalized.
   Change it ONLY if it is actually wrong, misspelled or for an uncommon sense.
2. "example" must use the word in the SAME meaning and part of speech as "turkish". If the sentence uses another
   sense (e.g. "The game ended in a draw." for Çizmek), REWRITE THE SENTENCE — do not change the translation to fit it.
3. "example" must be a complete, natural sentence (no fragments like "A kick to the knee."), with the target word
   exactly once, and respect the level: {rules}. No real people, brands or places.
4. "exampleTurkish" must be a correct, natural Turkish translation of the example.

5. The pos tag can be wrong. If the most common meaning at this level belongs to another part of speech
   (e.g. A1 "still" = "Hâlâ", an adverb), use that most common meaning anyway.

Do NOT rewrite a sentence that is already good: simple past tense, or a few words over the limit, is fine if the
vocabulary is simple and the sentence is natural. Only fix real problems (wrong sense, fragment, hard words,
clearly too long, wrong Turkish). Every sentence you write must sound natural to a native speaker — never produce
odd sentences like "I make a good sale today."

If everything is fine: ok=true and return all fields unchanged, note="".
Otherwise: ok=false, return the corrected fields (unchanged fields as they were) and a short English note
saying what was wrong. Return one object per input card with the same "key"."""

LEVEL_RULES_TEXT = "; ".join(f"{k}: {v}" for k, v in gc.LEVEL_RULES.items())


def build_prompt(items: list[dict]) -> str:
    lines = [RULES.format(rules=LEVEL_RULES_TEXT), "", "Cards (JSON):"]
    for it in items:
        card = {k: it[k] for k in ("key", "english", "pos", "level", "turkish", "example", "exampleTurkish")}
        if it.get("feedback"):
            card["previousAttemptRejected"] = it["feedback"]
        lines.append(json.dumps(card, ensure_ascii=False))
    return "\n".join(lines)


def run_agy(items: list[dict], model: str, timeout_s: int) -> list[dict]:
    """agy'yi boş bir klasörde, araç izni olmadan, yapılandırılmış çıktıyla çalıştırır."""
    with tempfile.TemporaryDirectory(prefix="wordlet-agy-") as workdir:
        for attempt in range(3):
            proc = subprocess.run(
                ["agy", "--model", model, "--output-format", "json",
                 "--json-schema", json.dumps(SCHEMA), "--print-timeout", f"{timeout_s}s",
                 "-p", build_prompt(items)],
                cwd=workdir, capture_output=True, text=True, timeout=timeout_s + 60,
            )
            try:
                out = json.loads(proc.stdout)
                if out.get("status") == "SUCCESS":
                    return out["structured_output"]["items"]
                print(f"  agy status={out.get('status')}, tekrar deneniyor...", flush=True)
            except (json.JSONDecodeError, KeyError, TypeError):
                print(f"  agy geçersiz çıktı (deneme {attempt + 1}): {proc.stderr.strip()[:200]}", flush=True)
    raise RuntimeError("agy 3 denemede geçerli cevap vermedi")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--level", choices=bw.LEVELS, required=True)
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--batch", type=int, default=40)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--limit", type=int)
    ap.add_argument("--timeout", type=int, default=600, help="agy çağrısı başına saniye")
    ap.add_argument("--dry-run", action="store_true", help="words.json'a yazma, sadece raporla")
    args = ap.parse_args()

    cefrj, freq = bw.load_cefrj(), bw.load_freq_rank()
    words = json.loads(bw.WORDS_JSON.read_text(encoding="utf-8"))
    by_id = {w["id"]: w for w in words}
    task = f"review_{args.level}"

    items = [
        {"key": w["id"], "english": w["english"], "pos": w.get("pos") or "?", "level": w["level"],
         "turkish": w["turkish"], "example": w.get("example", ""), "exampleTurkish": w.get("exampleTurkish", "")}
        for w in words if w["level"] == args.level
    ]
    items = items[: args.limit] if args.limit else items
    done = gc.cache_load(task)
    todo = [it for it in items if it["key"] not in done]
    print(f"{task}: {len(items)} kart, {len(items) - len(todo)} cache'te, {len(todo)} incelenecek", flush=True)

    failed: dict[str, dict] = {}
    for attempt in (1, 2):
        retry = []
        batches = [todo[i:i + args.batch] for i in range(0, len(todo), args.batch)]
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = {pool.submit(run_agy, b, args.model, args.timeout): b for b in batches}
            finished = 0
            for future in as_completed(futures):
                batch = futures[future]
                finished += len(batch)
                try:
                    results = {r["key"]: r for r in future.result()}
                except Exception as e:  # bir paket düşerse diğerleri devam etsin
                    print(f"  paket başarısız ({e}); bir sonraki çalıştırmada tekrar denenecek", flush=True)
                    continue
                accepted = []
                for it in batch:
                    r = results.get(it["key"])
                    if r is None:
                        retry.append({**it, "feedback": "card was missing from your answer"})
                        continue
                    issues = [] if r["ok"] else gc.problems(r["example"], it["english"], it["level"], cefrj, freq)
                    if not issues:
                        accepted.append({**r, "issues": []})
                    elif attempt == 1:
                        retry.append({**it, "feedback": "; ".join(issues)})
                    else:
                        failed[it["key"]] = {**r, "issues": issues}
                gc.cache_append(task, accepted)
                print(f"  [{attempt}] {finished}/{len(todo)}", flush=True)
        todo = retry
        if not todo:
            break

    results = gc.cache_load(task)
    rows, fail_rows = [], []
    for it in items:
        r = results.get(it["key"]) or failed.get(it["key"])
        if not r or r["ok"]:
            continue
        w = by_id[it["key"]]
        if r.get("issues"):
            fail_rows.append([w["id"], w["english"], r["example"], "; ".join(r["issues"])])
            continue
        rows.append([w["id"], w["english"], w.get("pos", ""), r.get("note", ""),
                     w["turkish"], r["turkish"], w.get("example", ""), r["example"], r["exampleTurkish"]])
        if not args.dry_run:
            w["turkish"] = r["turkish"].strip()
            w["example"] = r["example"].strip()
            w["exampleTurkish"] = r["exampleTurkish"].strip()

    gc.write_csv(f"review_{args.level}.csv",
                 ["id", "english", "pos", "note", "old_turkish", "new_turkish", "old_example", "new_example", "new_example_tr"],
                 rows)
    gc.write_csv(f"review_{args.level}_failures.csv", ["id", "english", "last_example", "issues"], fail_rows)
    reviewed = sum(1 for it in items if it["key"] in results)
    print(f"İncelenen: {reviewed}/{len(items)}, düzeltilen: {len(rows)}, doğrulamada kalan: {len(fail_rows)}")

    if args.dry_run:
        print("--dry-run: words.json değiştirilmedi.")
        return
    bw.WORDS_JSON.write_text(json.dumps(words, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("build_words.py yeniden çalışıyor...")
    bw.main()


if __name__ == "__main__":
    main()
