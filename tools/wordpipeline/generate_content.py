#!/usr/bin/env python3
"""
Wordlet kelime pipeline'ı — adım 2: Gemini ile içerik üretimi.

Ne yapar:
  examples  Şablon / seviyesinin üstünde / hedef kelimeyi içermeyen örnek cümleleri
            seviyeye uygun yeni cümlelerle değiştirir. Aynı istekte Türkçe karşılığı da
            kontrol eder; yanlışsa düzeltir.
  missing   CEFR-J'de A1/A2 olup veride olmayan temel kelimeleri ekler
            (Türkçe karşılık + örnek cümle + çevirisi).

Her değişiklik reports/ altına CSV olarak yazılır (elle kontrol için):
  example_changes.csv, translation_changes.csv, added_words.csv, generation_failures.csv
Sonunda build_words.py yeniden çalışır (seviye/rapor güncellenir).

Kurulum:
  echo 'GEMINI_API_KEY=...' > tools/wordpipeline/.env      # git'e girmez
  .venv/bin/python tools/wordpipeline/generate_content.py --list-models

Kullanım:
  # Önce küçük bir deneme (sadece A1, 20 kelime, words.json'a yazmaz):
  .venv/bin/python tools/wordpipeline/generate_content.py examples --level A1 --limit 20 --dry-run
  # Gerçek çalıştırma:
  .venv/bin/python tools/wordpipeline/generate_content.py examples --level A1
  .venv/bin/python tools/wordpipeline/generate_content.py missing --level A1

Yarıda kesilirse aynı komutu tekrar çalıştırın: cevaplar cache/ altında tutulur.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import build_words as bw  # noqa: E402
from lemminflect import getAllInflections, getAllLemmas  # noqa: E402

HERE = Path(__file__).parent
CACHE = HERE / "cache"
API_BASE = "https://generativelanguage.googleapis.com/v1beta"
DEFAULT_MODEL = "gemini-3.8-flash"  # --list-models ile hesabındaki modelleri gör
AGY_DEFAULT_MODEL = "gemini-3.1-pro-low"  # `agy models` ile listelenir
BACKEND = "agy"  # "agy": Antigravity CLI, "gemini": Gemini REST API (GEMINI_API_KEY gerekir)
BATCH_SIZE = 20
OFFLINE = False  # True: API çağırma, sadece cache'teki (agent'ların ürettiği) sonuçları uygula
WORKERS = 4  # aynı anahtarla eşzamanlı istek; 429 gelirse script bekleyip tekrar dener

# Seviyeye göre cümle uzunluğu ve dilbilgisi sınırı
LEVEL_RULES = {
    "A1": "max 8 words, present simple or 'can', only the most basic everyday words",
    "A2": "max 11 words, simple tenses (present/past/future with 'will'), common everyday words",
    "B1": "max 15 words, everyday topics, common B1 vocabulary",
    "B2": "max 20 words, natural adult English",
}


# ---------------------------------------------------------------------------
# Gemini
# ---------------------------------------------------------------------------

def api_key() -> str:
    key = os.environ.get("GEMINI_API_KEY")
    env_file = HERE / ".env"
    if not key and env_file.exists():
        for line in env_file.read_text().splitlines():
            if line.startswith("GEMINI_API_KEY="):
                key = line.split("=", 1)[1].strip().strip('"')
    if not key:
        sys.exit("GEMINI_API_KEY bulunamadı. tools/wordpipeline/.env dosyasına ekleyin.")
    return key


def http_json(url: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json", "x-goog-api-key": api_key()},
        method="POST" if data else "GET",
    )
    with urllib.request.urlopen(req, timeout=300) as res:
        return json.loads(res.read())


# Bu iş derin akıl yürütme istemiyor; düşünmeyi kısmak cevabı ciddi hızlandırır.
# Model desteklemezse (400) ayarsız devam edilir.
_use_thinking_config = True


def _json_schema(schema):
    """Gemini şeması ("ARRAY", "OBJECT") -> standart JSON Schema (küçük harf tipler)."""
    if isinstance(schema, dict):
        return {k: (v.lower() if k == "type" else _json_schema(v)) for k, v in schema.items()}
    if isinstance(schema, list):
        return [_json_schema(v) for v in schema]
    return schema


def agy(prompt: str, schema: dict, model: str, timeout_s: int = 600) -> list[dict]:
    """Antigravity CLI'yı boş bir klasörde, araç izni olmadan, yapılandırılmış çıktıyla çalıştırır."""
    wrapped = {"type": "object", "properties": {"items": _json_schema(schema)}, "required": ["items"]}
    with tempfile.TemporaryDirectory(prefix="wordlet-agy-") as workdir:
        for attempt in range(3):
            proc = subprocess.run(
                ["agy", "--model", model, "--output-format", "json", "--json-schema", json.dumps(wrapped),
                 "--print-timeout", f"{timeout_s}s", "-p", prompt],
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


def generate(prompt: str, schema: dict, model: str) -> list[dict]:
    return agy(prompt, schema, model) if BACKEND == "agy" else gemini(prompt, schema, model)


def gemini(prompt: str, schema: dict, model: str) -> list[dict]:
    global _use_thinking_config
    url = f"{API_BASE}/models/{model}:generateContent"
    for attempt in range(6):
        config = {
            "temperature": 0.4,
            "responseMimeType": "application/json",
            "responseSchema": schema,
        }
        if _use_thinking_config:
            config["thinkingConfig"] = {"thinkingLevel": "low"}
        body = {"contents": [{"role": "user", "parts": [{"text": prompt}]}], "generationConfig": config}
        try:
            res = http_json(url, body)
            text = "".join(p.get("text", "") for p in res["candidates"][0]["content"]["parts"])
            return json.loads(text)
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")[:300]
            if e.code == 400 and _use_thinking_config and "thinking" in detail.lower():
                print("  Model thinkingLevel desteklemiyor, ayarsız devam ediliyor.")
                _use_thinking_config = False
                continue
            if e.code in (429, 500, 502, 503, 504):
                wait = min(90, 10 * 2 ** attempt)
                print(f"  Gemini {e.code}, {wait} sn bekleniyor...")
                time.sleep(wait)
                continue
            sys.exit(f"Gemini hatası {e.code}: {detail}")
        except (TimeoutError, urllib.error.URLError, ConnectionError) as e:
            wait = min(90, 10 * 2 ** attempt)
            print(f"  Bağlantı/zaman aşımı ({e}), {wait} sn sonra tekrar...")
            time.sleep(wait)
        except (KeyError, IndexError, json.JSONDecodeError) as e:
            print(f"  Geçersiz cevap ({e}), tekrar deneniyor...")
            time.sleep(3)
    raise RuntimeError("Gemini 6 denemede cevap vermedi")


def list_models() -> None:
    res = http_json(f"{API_BASE}/models?pageSize=200")
    for m in res.get("models", []):
        if "generateContent" in m.get("supportedGenerationMethods", []):
            print(m["name"].removeprefix("models/"))


# ---------------------------------------------------------------------------
# Cache (yarıda kesilirse devam edebilmek için)
# ---------------------------------------------------------------------------

def cache_load(task: str) -> dict[str, dict]:
    path = CACHE / f"{task}.jsonl"
    if not path.exists():
        return {}
    out = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            row = json.loads(line)
            out[row["key"]] = row
    return out


def cache_append(task: str, rows: list[dict]) -> None:
    CACHE.mkdir(exist_ok=True)
    with (CACHE / f"{task}.jsonl").open("a", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")


# ---------------------------------------------------------------------------
# Doğrulama
# ---------------------------------------------------------------------------

def target_forms(english: str) -> set[str]:
    base = english.strip().lower()
    forms = {base}
    for lemmas in getAllLemmas(base).values():
        forms.update(lemmas)
    for lemma in list(forms):
        for infl in getAllInflections(lemma).values():
            forms.update(infl)
    return forms


def contains_target(sentence: str, english: str) -> bool:
    if " " in english.strip() or "-" in english:
        return english.strip().lower() in sentence.lower()
    tokens = {t.lower() for t in bw.TOKEN_RE.findall(sentence)}
    return bool(tokens & target_forms(english))


def problems(sentence: str, english: str, level: str, cefrj, freq) -> list[str]:
    issues = []
    if not sentence.strip():
        return ["boş cümle"]
    if not contains_target(sentence, english):
        issues.append(f"cümle '{english}' kelimesini içermiyor")
    hard = bw.hard_tokens(sentence, english, level, cefrj, freq)
    if len(hard) > bw.MAX_HARD_TOKENS:
        issues.append(f"{level} için zor kelimeler: {', '.join(hard)}")
    return issues


# ---------------------------------------------------------------------------
# Prompt'lar
# ---------------------------------------------------------------------------

EXAMPLE_SCHEMA = {
    "type": "ARRAY",
    "items": {
        "type": "OBJECT",
        "properties": {
            "key": {"type": "STRING"},
            "turkish": {"type": "STRING"},
            "turkishWasWrong": {"type": "BOOLEAN"},
            "example": {"type": "STRING"},
            "exampleTurkish": {"type": "STRING"},
        },
        "required": ["key", "turkish", "turkishWasWrong", "example", "exampleTurkish"],
    },
}

MISSING_SCHEMA = {
    "type": "ARRAY",
    "items": {
        "type": "OBJECT",
        "properties": {
            "key": {"type": "STRING"},
            "skip": {"type": "BOOLEAN"},
            "english": {"type": "STRING"},
            "turkish": {"type": "STRING"},
            "example": {"type": "STRING"},
            "exampleTurkish": {"type": "STRING"},
        },
        "required": ["key", "skip", "english", "turkish", "example", "exampleTurkish"],
    },
}

COMMON_RULES = """You are building vocabulary flashcards for a mobile app that teaches English to native Turkish speakers.
Rules for every example sentence:
- Natural, everyday English that a learner could actually say or hear. No textbook clichés
  like "I want to understand the concept of X" or "This is a perfect example of X".
- Use the target word exactly once, in the meaning given by its Turkish translation and part of speech.
- Respect the CEFR level limit given for each item: {rules}
- No names of real people, brands or places.
- exampleTurkish: a natural Turkish translation of the sentence (not word-by-word).
Return one JSON object per input item, with the same "key"."""


def example_prompt(items: list[dict]) -> str:
    rules = "; ".join(f"{k}: {v}" for k, v in LEVEL_RULES.items())
    lines = [COMMON_RULES.format(rules=rules), "",
             "Also check the Turkish translation (\"turkish\"). It must be the most common meaning of the English word",
             "for its part of speech, short (1-3 words), and in dictionary form. If it is wrong or unnatural, set",
             "turkishWasWrong=true and give the corrected translation; otherwise return it unchanged.",
             "Capitalize the first letter of the Turkish translation like the input.", "", "Items:"]
    for it in items:
        line = f'- key={it["key"]} | word="{it["english"]}" | pos={it.get("pos") or "?"} | level={it["level"]} | turkish="{it["turkish"]}"'
        if it.get("feedback"):
            line += f' | PREVIOUS ATTEMPT REJECTED: {it["feedback"]}'
        lines.append(line)
    return "\n".join(lines)


def missing_prompt(items: list[dict]) -> str:
    rules = "; ".join(f"{k}: {v}" for k, v in LEVEL_RULES.items())
    lines = [COMMON_RULES.format(rules=rules), "",
             "Each item is a word missing from the app. Provide:",
             "- english: the word as a flashcard headword, first letter capitalized (months/days keep capitals).",
             "- turkish: the most common Turkish meaning for that part of speech, 1-3 words, dictionary form",
             "  (verbs end in -mek/-mak), first letter capitalized.",
             "- skip=true only if the word cannot be a useful standalone flashcard (e.g. pure interjection",
             "  with no Turkish equivalent). Otherwise skip=false.", "", "Items:"]
    for it in items:
        line = f'- key={it["key"]} | word="{it["english"]}" | pos={it["pos"]} | level={it["level"]}'
        if it.get("feedback"):
            line += f' | PREVIOUS ATTEMPT REJECTED: {it["feedback"]}'
        lines.append(line)
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Görevler
# ---------------------------------------------------------------------------

def run_batches(task, items, prompt_fn, schema, model, cefrj, freq):
    """items: [{key, english, level, ...}] → {key: result}. Başarısızları bir kez geri bildirimle tekrar dener.
    Sadece doğrulamayı geçenler cache'e yazılır; başarısızlar bir sonraki çalıştırmada yeniden denenir."""
    done = cache_load(task)
    failed: dict[str, dict] = {}
    todo = [it for it in items if it["key"] not in done]
    print(f"{task}: {len(items)} öğe, {len(items) - len(todo)} cache'te, {len(todo)} üretilecek")
    if OFFLINE:
        print(f"  --offline: {len(todo)} öğe atlandı (API çağrılmıyor)")
        return {**failed, **done}

    for attempt in (1, 2):
        retry = []
        batches = [todo[i:i + BATCH_SIZE] for i in range(0, len(todo), BATCH_SIZE)]
        # Tek anahtarın kotası içinde paralel istek; doğrulama ve cache ana thread'de
        with ThreadPoolExecutor(max_workers=WORKERS) as pool:
            futures = {pool.submit(generate, prompt_fn(b), schema, model): b for b in batches}
            finished = 0
            for future in as_completed(futures):
                batch = futures[future]
                finished += len(batch)
                print(f"  [{attempt}] {finished}/{len(todo)}", flush=True)
                try:
                    results = {r["key"]: r for r in future.result() if "key" in r}
                except Exception as e:  # bir paket düşerse diğerleri devam etsin
                    print(f"  paket başarısız ({e}); bir sonraki çalıştırmada tekrar denenecek", flush=True)
                    continue
                retry += validate_batch(task, batch, results, attempt, cefrj, freq, failed)
        todo = retry
        if not todo:
            break
    return {**failed, **cache_load(task)}


def validate_batch(task, batch, results, attempt, cefrj, freq, failed) -> list[dict]:
    """Geçenleri cache'e yazar, başarısızları failed'e koyar; tekrar denenecekleri döndürür."""
    retry, accepted = [], []
    for it in batch:
        r = results.get(it["key"])
        if r is None:
            retry.append({**it, "feedback": "item was missing from your answer"})
            continue
        if r.get("skip"):
            accepted.append({**r, "issues": []})
            continue
        issues = problems(r["example"], r.get("english") or it["english"], it["level"], cefrj, freq)
        if not issues:
            accepted.append({**r, "issues": []})
        elif attempt == 1:
            retry.append({**it, "feedback": "; ".join(issues)})
        else:
            failed[it["key"]] = {**r, "issues": issues}
    cache_append(task, accepted)
    return retry


def write_csv(name, header, rows):
    with (bw.REPORTS / name).open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


def example_items(words, level, cefrj, freq) -> list[dict]:
    """Örnek cümlesi yeniden yazılması gereken kelimeler."""
    items = []
    for w in words:
        if level and w["level"] != level:
            continue
        needs = (
            w.get("exampleIsTemplate")
            or not contains_target(w.get("example", ""), w["english"])
            or len(bw.hard_tokens(w.get("example", ""), w["english"], w["level"], cefrj, freq)) > bw.MAX_HARD_TOKENS
        )
        if needs:
            items.append({"key": w["id"], "english": w["english"], "pos": w.get("pos"),
                          "level": w["level"], "turkish": w["turkish"]})
    return items


def missing_items(words, level) -> list[dict]:
    """CEFR-J A1/A2 olup veride olmayan kelimeler."""
    have = {w["english"].strip().lower() for w in words}
    items, seen = [], set()
    with (bw.REPORTS / "missing_core_words.csv").open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            head = row["headword"]
            if head in have or head in seen or (level and row["cefr"] != level):
                continue
            seen.add(head)  # aynı kelimenin farklı türleri: en yaygın (ilk) tür
            items.append({"key": f"{head}|{row['pos']}", "english": head, "pos": row["pos"], "level": row["cefr"]})
    return items


def task_examples(args, words, cefrj, freq):
    items = example_items(words, args.level, cefrj, freq)
    items = items[: args.limit] if args.limit else items

    results = run_batches("examples", items, example_prompt, EXAMPLE_SCHEMA, args.model, cefrj, freq)
    by_id = {w["id"]: w for w in words}
    ex_rows, tr_rows, fail_rows = [], [], []
    for it in items:
        r = results.get(it["key"])
        if not r:
            continue
        w = by_id[it["key"]]
        if r["issues"]:
            fail_rows.append([w["id"], w["english"], w["level"], r["example"], "; ".join(r["issues"])])
            continue
        ex_rows.append([w["id"], w["english"], w["level"], w.get("example", ""), r["example"], r["exampleTurkish"]])
        if r["turkishWasWrong"] and r["turkish"].strip() and r["turkish"].strip() != w["turkish"]:
            tr_rows.append([w["id"], w["english"], w.get("pos", ""), w["turkish"], r["turkish"].strip()])
        if not args.dry_run:
            w["example"] = r["example"].strip()
            w["exampleTurkish"] = r["exampleTurkish"].strip()
            if r["turkishWasWrong"] and r["turkish"].strip():
                w["turkish"] = r["turkish"].strip()

    write_csv("example_changes.csv", ["id", "english", "level", "old_example", "new_example", "new_example_tr"], ex_rows)
    write_csv("translation_changes.csv", ["id", "english", "pos", "old_turkish", "new_turkish"], tr_rows)
    write_csv("generation_failures.csv", ["id", "english", "level", "last_example", "issues"], fail_rows)
    print(f"Cümle değişti: {len(ex_rows)}, çeviri düzeltildi: {len(tr_rows)}, başarısız: {len(fail_rows)}")


def task_missing(args, words, cefrj, freq):
    have = {w["english"].strip().lower() for w in words}
    items = missing_items(words, args.level)
    items = items[: args.limit] if args.limit else items

    results = run_batches("missing", items, missing_prompt, MISSING_SCHEMA, args.model, cefrj, freq)
    next_id = max(int(w["id"]) for w in words if w["id"].isdigit()) + 1
    added, fail_rows = [], []
    for it in items:
        r = results.get(it["key"])
        if not r or r.get("skip"):
            continue
        if r["issues"]:
            fail_rows.append([it["english"], it["level"], r["example"], "; ".join(r["issues"])])
            continue
        if r["english"].strip().lower() in have:
            continue
        new = {
            "english": r["english"].strip(),
            "turkish": r["turkish"].strip(),
            "example": r["example"].strip(),
            "id": str(next_id),
            "exampleTurkish": r["exampleTurkish"].strip(),
        }
        next_id += 1
        have.add(new["english"].lower())
        added.append([new["id"], new["english"], it["pos"], it["level"], new["turkish"], new["example"], new["exampleTurkish"]])
        if not args.dry_run:
            words.append(new)

    write_csv("added_words.csv", ["id", "english", "pos", "level", "turkish", "example", "example_tr"], added)
    write_csv("generation_failures_missing.csv", ["english", "level", "last_example", "issues"], fail_rows)
    print(f"Eklenen kelime: {len(added)}, başarısız: {len(fail_rows)}")


AGENT_WORK = HERE / "agent_work"


def read_jsonl(path: Path) -> list[dict]:
    rows = []
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.strip():
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as e:
                sys.exit(f"{path}:{n} geçersiz JSON: {e}")
    return rows


def agent_issues(task, row, item, cefrj, freq) -> list[str]:
    required = ["key", "turkish", "example", "exampleTurkish"] + (["english", "skip"] if task == "missing" else ["turkishWasWrong"])
    missing = [k for k in required if k not in row]
    if missing:
        return [f"eksik alan: {', '.join(missing)}"]
    if row.get("skip"):
        return []
    return problems(row["example"], row.get("english") or item["english"], item["level"], cefrj, freq)


def cmd_export(task, level, parts, words, cefrj, freq):
    items = example_items(words, level, cefrj, freq) if task == "examples" else missing_items(words, level)
    done = cache_load(task)
    items = [it for it in items if it["key"] not in done]
    AGENT_WORK.mkdir(exist_ok=True)
    size = -(-len(items) // parts) if items else 0
    for i in range(parts):
        chunk = items[i * size:(i + 1) * size]
        if chunk:
            path = AGENT_WORK / f"{task}_{level or 'all'}_part{i + 1}.json"
            path.write_text(json.dumps(chunk, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
            print(f"{path.relative_to(bw.ROOT)}: {len(chunk)} öğe")


def cmd_check(task, input_path, output_path, cefrj, freq, do_import=False):
    items = {it["key"]: it for it in json.loads(input_path.read_text(encoding="utf-8"))}
    rows = read_jsonl(output_path)
    got = {r.get("key"): r for r in rows}
    bad, good = [], []
    for key, item in items.items():
        r = got.get(key)
        issues = ["çıktıda yok"] if r is None else agent_issues(task, r, item, cefrj, freq)
        (bad if issues else good).append((key, item, r, issues))
    for key, item, r, issues in bad:
        print(f"HATA key={key} word={item['english']} level={item['level']}: {'; '.join(issues)}")
    print(f"{len(good)}/{len(items)} geçti, {len(bad)} hatalı")
    if do_import and good:
        done = cache_load(task)
        new = [{**r, "issues": []} for _, _, r, _ in good if r["key"] not in done]
        cache_append(task, new)
        print(f"cache'e eklendi: {len(new)}")
    return not bad


def main():
    global WORKERS, OFFLINE, BACKEND
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("task", nargs="?", choices=["examples", "missing", "export", "check", "import"])
    ap.add_argument("paths", nargs="*", help="export: TASK | check/import: TASK INPUT.json OUTPUT.jsonl")
    ap.add_argument("--parts", type=int, default=4, help="export: kaç parçaya bölünsün")
    ap.add_argument("--offline", action="store_true", help="API çağırma, sadece cache'i uygula")
    ap.add_argument("--level", choices=bw.LEVELS)
    ap.add_argument("--limit", type=int, help="en fazla bu kadar öğe işle (deneme için)")
    ap.add_argument("--backend", choices=["agy", "gemini"], default=BACKEND)
    ap.add_argument("--model", help=f"varsayılan: agy={AGY_DEFAULT_MODEL}, gemini={DEFAULT_MODEL}")
    ap.add_argument("--dry-run", action="store_true", help="words.json'a yazma, sadece raporla")
    ap.add_argument("--list-models", action="store_true")
    ap.add_argument("--workers", type=int, default=WORKERS, help="eşzamanlı istek sayısı")
    args = ap.parse_args()
    WORKERS = max(1, args.workers)
    BACKEND = args.backend
    args.model = args.model or os.environ.get("GEMINI_MODEL") or (AGY_DEFAULT_MODEL if BACKEND == "agy" else DEFAULT_MODEL)
    if args.offline:
        OFFLINE = True

    if args.list_models:
        list_models()
        return
    if not args.task:
        ap.error("task gerekli: examples veya missing")

    cefrj, freq = bw.load_cefrj(), bw.load_freq_rank()
    words = json.loads(bw.WORDS_JSON.read_text(encoding="utf-8"))

    if args.task == "export":
        cmd_export(args.paths[0], args.level, args.parts, words, cefrj, freq)
        return
    if args.task in ("check", "import"):
        task, inp, out = args.paths[0], Path(args.paths[1]), Path(args.paths[2])
        ok = cmd_check(task, inp, out, cefrj, freq, do_import=args.task == "import")
        sys.exit(0 if ok or args.task == "import" else 1)
    if args.task == "examples":
        task_examples(args, words, cefrj, freq)
    else:
        task_missing(args, words, cefrj, freq)

    if args.dry_run:
        print("--dry-run: words.json değiştirilmedi. Raporlar reports/ altında.")
        return
    bw.WORDS_JSON.write_text(json.dumps(words, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("\nbuild_words.py yeniden çalışıyor (seviye, tür ve raporlar güncelleniyor)...")
    bw.main()


if __name__ == "__main__":
    main()
