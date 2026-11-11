#!/usr/bin/env python3
"""Segredo do motor próprio (Godot 4.7 "spolia").

Gera uma vez, fora do repositório, os valores secretos que o editor e os
templates compilados compartilham: chave AES do .pck, semente da máscara da
chave, sais da derivação, tempero do IV, mágicas do .pck e do GDScript
binário, permutação dos tokens e fluxo que embaralha os identificadores.

Uso:
    python3 Tools/motor/segredo.py gerar          # cria o JSON se não existir
    python3 Tools/motor/segredo.py cabecalho DIR  # escreve DIR/core/io/spolia_segredo.gen.h
    python3 Tools/motor/segredo.py chave          # imprime a chave (64 hex)
    python3 Tools/motor/segredo.py credenciais    # grava a chave nos presets (.godot/export_credentials.cfg)

Perder o JSON não quebra jogos já lançados, mas o próximo build tem de ser
feito com um segredo novo e todos os templates recompilados junto do editor.
"""

import json
import os
import random
import re
import secrets
import sys
from pathlib import Path

CAMINHO = Path(os.environ.get("SPOLIA_SEGREDO", Path.home() / ".config/falsecontinuum/motor_segredo.json"))
RAIZ_PROJETO = Path(__file__).resolve().parents[2]

# Faixa útil do tipo do token: 7 bits, e o 0 (EMPTY) tem de continuar 0, senão
# o codificador grava um token com índice em 5 bytes e perde o índice.
TOKEN_FAIXA = 127


def gerar():
    if CAMINHO.exists():
        print(f"já existe: {CAMINHO}")
        return
    rng = random.SystemRandom()
    perm = list(range(1, TOKEN_FAIXA + 1))
    rng.shuffle(perm)

    def u32_sem_zero():
        while True:
            v = secrets.randbits(32)
            if v not in (0, 0x43504447, 0x43454447):
                return v

    dados = {
        "chave": secrets.token_hex(32),
        "mascara_semente": secrets.randbits(64),
        "sal_cfb": secrets.token_hex(32),
        "sal_ofb": secrets.token_hex(32),
        "tempero_iv": secrets.token_hex(16),
        "xor_tamanho": secrets.randbits(64),
        "magica_pck": u32_sem_zero(),
        "magica_gdsc": u32_sem_zero(),
        "versao_tokens": rng.randrange(1000, 60000),
        "perm_tokens": perm,  # perm[i - 1] = valor gravado para o tipo i
        "fluxo_ident": secrets.token_hex(32),
        "xor_linha": secrets.randbits(32),
    }
    CAMINHO.parent.mkdir(parents=True, exist_ok=True)
    CAMINHO.write_text(json.dumps(dados, indent=1))
    CAMINHO.chmod(0o600)
    print(f"segredo gerado em {CAMINHO} — guarde uma cópia fora desta máquina")


def ler():
    if not CAMINHO.exists():
        sys.exit(f"segredo não encontrado em {CAMINHO}; rode: segredo.py gerar")
    return json.loads(CAMINHO.read_text())


def _bytes_c(hexa):
    return ", ".join(f"0x{b:02x}" for b in bytes.fromhex(hexa))


def cabecalho(dir_godot):
    s = ler()
    perm = s["perm_tokens"]
    inv = [0] * (TOKEN_FAIXA + 1)
    for tipo, valor in enumerate(perm, start=1):
        inv[valor] = tipo
    cod = [0] + perm
    destino = Path(dir_godot) / "core/io/spolia_segredo.gen.h"
    destino.write_text(
        f"""/* Gerado por Tools/motor/segredo.py (ProjectSpolia). Não versionar. */
#pragma once

#include <cstdint>

#define SPOLIA_PACK_MAGIC 0x{s["magica_pck"]:08x}u
#define SPOLIA_GDSC_MAGIC 0x{s["magica_gdsc"]:08x}u
#define SPOLIA_TOKENS_VERSAO {s["versao_tokens"]}u
#define SPOLIA_XOR_TAMANHO 0x{s["xor_tamanho"]:016x}ull
#define SPOLIA_XOR_LINHA 0x{s["xor_linha"]:08x}u
#define SPOLIA_MASCARA_SEMENTE 0x{s["mascara_semente"]:016x}ull

static constexpr uint8_t SPOLIA_SAL_CFB[32] = {{ {_bytes_c(s["sal_cfb"])} }};
static constexpr uint8_t SPOLIA_SAL_OFB[32] = {{ {_bytes_c(s["sal_ofb"])} }};
static constexpr uint8_t SPOLIA_TEMPERO_IV[16] = {{ {_bytes_c(s["tempero_iv"])} }};
static constexpr uint8_t SPOLIA_FLUXO_IDENT[32] = {{ {_bytes_c(s["fluxo_ident"])} }};

/* Tipo do token -> valor gravado (0 fica 0) e o inverso. */
static constexpr uint8_t SPOLIA_TOKEN_COD[{TOKEN_FAIXA + 1}] = {{ {", ".join(map(str, cod))} }};
static constexpr uint8_t SPOLIA_TOKEN_DEC[{TOKEN_FAIXA + 1}] = {{ {", ".join(map(str, inv))} }};

/* Mesma SplitMix64 de core_builders.py: a chave fica gravada com esta máscara. */
static inline void spolia_mascara(uint8_t r_out[32]) {{
	uint64_t estado = SPOLIA_MASCARA_SEMENTE;
	for (int i = 0; i < 4; i++) {{
		estado += 0x9E3779B97F4A7C15ull;
		uint64_t z = estado;
		z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
		z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
		z ^= z >> 31;
		for (int b = 0; b < 8; b++) {{
			r_out[i * 8 + b] = (uint8_t)(z >> (b * 8));
		}}
	}}
}}
"""
    )
    print(f"cabeçalho escrito em {destino}")


def credenciais():
    """Põe a chave em todos os presets de .godot/export_credentials.cfg."""
    chave = ler()["chave"]
    cfg = RAIZ_PROJETO / ".godot/export_credentials.cfg"
    texto = cfg.read_text()
    novo, n = re.subn(r'^script_encryption_key=".*"$', f'script_encryption_key="{chave}"', texto, flags=re.M)
    cfg.write_text(novo)
    print(f"chave gravada em {n} preset(s) de {cfg}")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "gerar":
        gerar()
    elif cmd == "cabecalho" and len(sys.argv) > 2:
        cabecalho(sys.argv[2])
    elif cmd == "chave":
        print(ler()["chave"])
    elif cmd == "credenciais":
        credenciais()
    else:
        sys.exit(__doc__)
