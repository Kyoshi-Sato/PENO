#!/usr/bin/env python3
"""
Testa a API de lições da Ciclica Interactive.

Uso:
    python test_api.py                        # testa catálogo + lição 1
    python test_api.py --lesson 3             # testa catálogo + lição 3
    python test_api.py --all                  # testa catálogo + TODAS as lições
    python test_api.py --url http://outro-host:3000

Não requer bibliotecas externas — só stdlib.
"""

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from typing import Any


DEFAULT_BASE_URL = "https://api.ciclicainteractive.com"
DEFAULT_API_KEY = "chave_secreta_godot"
DEFAULT_TIMEOUT = 30  # segundos


# ─────────────────────────────────────────────────────────
#  HTTP
# ─────────────────────────────────────────────────────────

def http_get(url: str, api_key: str, timeout: int = DEFAULT_TIMEOUT) -> tuple[int, bytes, float]:
    """
    GET simples. Retorna (status_code, body_bytes, elapsed_seconds).
    Levanta URLError em erros de rede.
    """
    req = urllib.request.Request(
        url,
        headers={
            "x-api-key": api_key,
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "libras-api-tester/1.0",
        },
        method="GET",
    )
    start = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read()
            elapsed = time.perf_counter() - start
            return resp.status, body, elapsed
    except urllib.error.HTTPError as e:
        elapsed = time.perf_counter() - start
        return e.code, e.read(), elapsed


# ─────────────────────────────────────────────────────────
#  Helpers de formatação
# ─────────────────────────────────────────────────────────

BOLD = "\033[1m"
DIM = "\033[2m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[31m"
CYAN = "\033[36m"
RESET = "\033[0m"


def hr(char: str = "─", width: int = 60) -> None:
    print(char * width)


def section(title: str) -> None:
    print()
    hr("═")
    print(f"{BOLD}  {title}{RESET}")
    hr("═")


def ok(msg: str) -> None:
    print(f"  {GREEN}✓{RESET} {msg}")


def warn(msg: str) -> None:
    print(f"  {YELLOW}!{RESET} {msg}")


def fail(msg: str) -> None:
    print(f"  {RED}✗{RESET} {msg}")


def info(msg: str) -> None:
    print(f"  {DIM}·{RESET} {msg}")


def human_size(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f} {unit}" if unit != "B" else f"{n} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


# ─────────────────────────────────────────────────────────
#  Testes
# ─────────────────────────────────────────────────────────

def parse_json(body: bytes) -> Any:
    try:
        return json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as e:
        fail(f"Corpo não é JSON válido: {e}")
        info(f"Primeiros 200 bytes: {body[:200]!r}")
        return None


def test_catalog(base_url: str, api_key: str) -> list[dict]:
    """Testa GET /licoes. Retorna a lista de lições parseada (ou vazia)."""
    section("GET /licoes  (catálogo)")

    url = f"{base_url}/licoes"
    info(f"URL: {url}")

    try:
        status, body, elapsed = http_get(url, api_key)
    except Exception as e:
        fail(f"Erro de rede: {e}")
        return []

    info(f"Status: {status}   Tempo: {elapsed*1000:.0f}ms   Tamanho: {human_size(len(body))}")

    if status != 200:
        fail(f"HTTP {status}")
        info(f"Corpo: {body[:400]!r}")
        return []
    ok("HTTP 200")

    data = parse_json(body)
    if data is None:
        return []
    ok("JSON parseado")

    if not isinstance(data, list):
        fail(f"Esperava lista, veio {type(data).__name__}")
        info(f"Preview: {str(data)[:200]}")
        return []
    ok(f"É lista com {len(data)} elementos")

    if len(data) == 0:
        warn("Catálogo vazio")
        return []

    # Valida shape de cada entrada
    print()
    print(f"  {BOLD}Lições:{RESET}")
    valid = []
    for i, entry in enumerate(data):
        if not isinstance(entry, dict):
            fail(f"  [{i}] Não é dict: {entry!r}")
            continue
        eid = entry.get("id") or entry.get("id_exercicio")
        nome = entry.get("nome") or entry.get("nome_exercicio", "")
        if eid is None:
            fail(f"  [{i}] Sem campo 'id' ou 'id_exercicio'")
            continue
        print(f"    {CYAN}#{eid:<4}{RESET} {nome}")
        valid.append({"id": int(eid), "nome": str(nome)})

    print()
    ok(f"{len(valid)}/{len(data)} entradas válidas")
    return valid


def test_lesson(base_url: str, api_key: str, lesson_id: int) -> bool:
    """Testa GET /exercicio/{id}. Retorna True se passou nas validações."""
    section(f"GET /exercicio/{lesson_id}")

    url = f"{base_url}/exercicio/{lesson_id}"
    info(f"URL: {url}")

    try:
        status, body, elapsed = http_get(url, api_key)
    except Exception as e:
        fail(f"Erro de rede: {e}")
        return False

    info(f"Status: {status}   Tempo: {elapsed*1000:.0f}ms   Tamanho: {human_size(len(body))}")

    if status != 200:
        fail(f"HTTP {status}")
        info(f"Corpo: {body[:400]!r}")
        return False
    ok("HTTP 200")

    data = parse_json(body)
    if data is None:
        return False
    ok("JSON parseado")

    if not isinstance(data, dict):
        fail(f"Esperava objeto, veio {type(data).__name__}")
        return False

    # Campos top-level
    nome_ex = data.get("nome_exercicio", "")
    sinais = data.get("sinais")
    print(f"  nome_exercicio: {CYAN}{nome_ex!r}{RESET}")

    if not isinstance(sinais, list):
        fail(f"'sinais' ausente ou não é lista (veio {type(sinais).__name__})")
        return False
    ok(f"'sinais' é lista com {len(sinais)} elementos")

    if len(sinais) == 0:
        warn("Nenhum sinal — nada pra validar")
        return True

    # Valida cada sinal
    print()
    print(f"  {BOLD}Sinais:{RESET}")

    total_ok = 0
    for i, s in enumerate(sinais):
        print(f"    {CYAN}[{i}]{RESET}")
        if not isinstance(s, dict):
            fail(f"    Não é dict: {s!r}")
            continue

        nome_sinal = s.get("nome_sinal", "")
        anim_lib = s.get("anim_lib", "")
        json_sinal = s.get("json_sinal", None)

        # nome_sinal
        if not isinstance(nome_sinal, str) or not nome_sinal:
            fail(f"    nome_sinal ausente/inválido")
        else:
            print(f"      nome_sinal:  {nome_sinal!r}")

        # anim_lib — esperamos string com [gd_resource type="Animation"...]
        if not isinstance(anim_lib, str):
            fail(f"    anim_lib não é string (é {type(anim_lib).__name__})")
        elif not anim_lib:
            fail(f"    anim_lib vazio")
        else:
            head = anim_lib[:80].replace("\n", "\\n")
            print(f"      anim_lib:    {DIM}{len(anim_lib)} chars — começa com: {head}...{RESET}")
            if "[gd_resource" not in anim_lib[:200]:
                warn("    anim_lib não começa com [gd_resource — verifique formato")
            elif 'type="Animation"' not in anim_lib[:200]:
                warn('    anim_lib não parece ser type="Animation"')

        # json_sinal — pode chegar como Dictionary ou como string serializada
        parsed_sinal = None
        if isinstance(json_sinal, dict):
            print(f"      json_sinal:  {DIM}Dictionary com {len(json_sinal)} keys: {list(json_sinal.keys())}{RESET}")
            parsed_sinal = json_sinal
        elif isinstance(json_sinal, str):
            warn(f"    json_sinal veio como STRING ({len(json_sinal)} chars) — precisa JSON.parse")
            try:
                parsed_sinal = json.loads(json_sinal)
                info(f"      Após parse: {list(parsed_sinal.keys()) if isinstance(parsed_sinal, dict) else type(parsed_sinal).__name__}")
            except json.JSONDecodeError as e:
                fail(f"    E parse falha: {e}")
        else:
            fail(f"    json_sinal ausente ou tipo inesperado ({type(json_sinal).__name__})")

        # Validação do conteúdo do json_sinal
        if isinstance(parsed_sinal, dict):
            info_ok = "video_info" in parsed_sinal
            frames_val = parsed_sinal.get("frames")
            frames_ok = isinstance(frames_val, list) and len(frames_val) > 0
            if info_ok and frames_ok:
                fps = parsed_sinal.get("video_info", {}).get("fps", "?")
                print(f"      landmarks:   {GREEN}{len(frames_val)} frames @ {fps}fps{RESET}")
                total_ok += 1
            else:
                if not info_ok:
                    fail("    json_sinal sem 'video_info'")
                if not frames_ok:
                    fail(f"    json_sinal sem 'frames' válidos (é {type(frames_val).__name__})")

    print()
    if total_ok == len(sinais):
        ok(f"Todos os {len(sinais)} sinais válidos")
        return True
    else:
        warn(f"{total_ok}/{len(sinais)} sinais válidos")
        return False


# ─────────────────────────────────────────────────────────
#  Main
# ─────────────────────────────────────────────────────────

def main():
    p = argparse.ArgumentParser(description="Testa a API de lições")
    p.add_argument("--url", default=DEFAULT_BASE_URL, help=f"URL base (default: {DEFAULT_BASE_URL})")
    p.add_argument("--key", default=DEFAULT_API_KEY, help="API key (x-api-key header)")
    p.add_argument("--lesson", type=int, default=1, help="Id da lição pra testar (default: 1)")
    p.add_argument("--all", action="store_true", help="Testa TODAS as lições do catálogo")
    args = p.parse_args()

    print(f"{BOLD}API base:{RESET} {args.url}")
    print(f"{BOLD}API key: {RESET} {args.key[:6]}…" if len(args.key) > 6 else args.key)

    catalog = test_catalog(args.url, args.key)

    if args.all:
        if not catalog:
            fail("Sem catálogo, não posso testar lições")
            sys.exit(1)
        results = []
        for entry in catalog:
            ok_ = test_lesson(args.url, args.key, entry["id"])
            results.append((entry["id"], entry["nome"], ok_))
        section("RESUMO")
        for lid, nome, ok_ in results:
            marker = f"{GREEN}✓{RESET}" if ok_ else f"{RED}✗{RESET}"
            print(f"  {marker} #{lid:<4} {nome}")
        n_ok = sum(1 for _, _, o in results if o)
        print()
        print(f"  {n_ok}/{len(results)} lições passaram")
        sys.exit(0 if n_ok == len(results) else 1)
    else:
        test_lesson(args.url, args.key, args.lesson)
        print()


if __name__ == "__main__":
    main()