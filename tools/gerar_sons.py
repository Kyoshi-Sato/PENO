#!/usr/bin/env python3
"""Gera os efeitos sonoros do HandSign em res://assets/audio/.

Por que sintetizar em vez de baixar
-----------------------------------
Os arquivos são versionados junto com o projeto, então precisam ter
procedência clara: um TCC não pode depender de um WAV de origem e licença
desconhecidas. Aqui cada som é uma função determinística deste arquivo —
qualquer pessoa reproduz byte a byte com `python3 tools/gerar_sons.py`.

Depende só da biblioteca padrão (math, struct, wave).

Paleta
------
Tudo é senoide com poucos harmônicos e decaimento exponencial: lê como
"marimba/sino", não como bipe de eletrodoméstico. As notas saem de uma
escala de dó maior, então dois sons quaisquer que se sobreponham na tela de
resultado continuam consoantes.

Registro
--------
A primeira versão vivia entre C5 e C7 (523 a 2093 Hz) e soava estridente. Esta
desceu uma oitava, mas NÃO mais do que isso, e o motivo é o alto-falante:

    o de um celular só começa a responder em torno de 400 Hz, cai uns 10 dB
    em 300 Hz e praticamente não emite nada abaixo de 200 Hz.

Ou seja, descer demais não deixa o som mais grave — deixa ele inaudível no
único aparelho que importa aqui. As fundamentais ficaram entre 196 e 1046 Hz,
com a maior parte do peso entre 260 e 780.

Profundidade veio de três lugares que não custam registro:

  1. menos conteúdo agudo (`HARMONICOS_PADRAO` foi de 0,32/0,12 para
     0,22/0,06 no 2º e 3º harmônicos);
  2. os agudos morrendo mais rápido que a fundamental
     (`AMORTECIMENTO_HARMONICO`), que é o que o ouvido lê como "abafado";
  3. decaimento geral mais lento — cauda longa soa como corpo, não como tique.

Onde a fundamental é baixa demais para o alto-falante (o som de falha, em
G3 = 196 Hz), o 2º harmônico entra forte de propósito: o ouvido reconstrói a
fundamental ausente a partir dele e o som continua lendo como grave mesmo num
alto-falante que não consegue emiti-la.
"""

import math
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44100
DESTINO = Path(__file__).resolve().parent.parent / "assets" / "audio"

# Ataque curto o bastante para soar instantâneo, longo o bastante para não
# estalar: um degrau em amostra cheia vira um clique audível no alto-falante.
ATAQUE_S = 0.004
# Rampa final pela mesma razão, no outro extremo do arquivo.
QUEDA_S = 0.006

# Peso do 2º, 3º e 4º harmônicos. Baixo de propósito: é a diferença entre
# "sino de igreja" e "despertador".
HARMONICOS_PADRAO = (1.0, 0.22, 0.06)
# Quanto mais rápido cada harmônico morre em relação à fundamental. É o
# parâmetro que mais controla a sensação de "abafado" — um instrumento real
# perde o brilho antes de perder o corpo.
AMORTECIMENTO_HARMONICO = 2.4

# Dó maior a partir de C3. Manter as notas nomeadas evita "261.63" solto no
# meio da definição de cada som. Ver "Registro" no cabeçalho para o motivo de
# a paleta parar em C6 embaixo e em G3 em cima.
NOTAS = {
    "G3": 196.00, "A3": 220.00,
    "C4": 261.63, "D4": 293.66, "E4": 329.63, "G4": 392.00, "A4": 440.00,
    "C5": 523.25, "D5": 587.33, "E5": 659.25, "G5": 783.99, "A5": 880.00,
    "C6": 1046.50,
}


def nota(nome_ou_hz):
    return NOTAS[nome_ou_hz] if isinstance(nome_ou_hz, str) else float(nome_ou_hz)


def sino(freq, dur, decaimento=4.5, harmonicos=None, ganho=1.0, sub=0.0):
    """Uma nota: soma de harmônicos sob um decaimento exponencial.

    `sub` acrescenta uma senoide uma oitava ABAIXO da fundamental, com o peso
    dado. É o que dá corpo sem descer o registro da melodia — mas custa
    headroom na normalização, então só vale onde a fundamental já é alta o
    bastante para a sub-oitava ainda cair na faixa útil do alto-falante.
    """
    if harmonicos is None:
        harmonicos = HARMONICOS_PADRAO
    n = int(SAMPLE_RATE * dur)
    f0 = nota(freq)
    saida = [0.0] * n
    for i in range(n):
        t = i / SAMPLE_RATE
        env = math.exp(-decaimento * t / dur) * ganho
        amostra = 0.0
        if sub > 0.0:
            amostra += sub * math.sin(math.pi * f0 * t)
        for k, peso in enumerate(harmonicos, start=1):
            # Harmônicos agudos morrem antes que a fundamental — é isso que
            # dá o "tlim" percussivo em vez de um órgão sustentado.
            amostra += peso * math.exp(
                -(k - 1) * AMORTECIMENTO_HARMONICO * t / dur
            ) * math.sin(2.0 * math.pi * f0 * k * t)
        saida[i] = amostra * env
    return saida


def silencio(dur):
    return [0.0] * int(SAMPLE_RATE * dur)


def sobrepor(base, extra, offset_s):
    """Mistura `extra` dentro de `base` a partir de offset_s (soma, não corta)."""
    inicio = int(SAMPLE_RATE * offset_s)
    faltam = inicio + len(extra) - len(base)
    if faltam > 0:
        base.extend([0.0] * faltam)
    for i, v in enumerate(extra):
        base[inicio + i] += v
    return base


def sequencia(eventos):
    """[(offset_s, amostras), ...] -> uma trilha só."""
    trilha = []
    for offset, amostras in eventos:
        trilha = sobrepor(trilha, amostras, offset)
    return trilha


def normalizar(amostras, pico=0.85):
    maior = max((abs(v) for v in amostras), default=0.0)
    if maior <= 0.0:
        return amostras
    fator = pico / maior
    return [v * fator for v in amostras]


def aplicar_rampas(amostras):
    n_atk = min(int(SAMPLE_RATE * ATAQUE_S), len(amostras))
    n_end = min(int(SAMPLE_RATE * QUEDA_S), len(amostras))
    for i in range(n_atk):
        # Cosseno elevado: derivada zero nas pontas, sem quina no envelope.
        amostras[i] *= 0.5 - 0.5 * math.cos(math.pi * i / n_atk)
    for i in range(n_end):
        amostras[len(amostras) - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / n_end)
    return amostras


def escrever(nome, amostras, pico=0.85):
    amostras = aplicar_rampas(normalizar(list(amostras), pico))
    quadros = b"".join(
        struct.pack("<h", max(-32768, min(32767, int(round(v * 32767.0)))))
        for v in amostras
    )
    caminho = DESTINO / ("%s.wav" % nome)
    with wave.open(str(caminho), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(quadros)
    dur_ms = 1000.0 * len(amostras) / SAMPLE_RATE
    print("  %-16s %6.0f ms  %6.1f KB" % (nome, dur_ms, len(quadros) / 1024.0))


# ═══════════════════════════════════════════════════════════
#  OS SONS
# ═══════════════════════════════════════════════════════════
#
# A ordem abaixo é a ordem em que o usuário os encontra no app.

def sons():
    # Toque de botão. O som mais repetido do app inteiro — por isso é o mais
    # curto e o mais neutro que dá para fazer. Ficou quase o dobro de longo
    # que na versão aguda: a 261 Hz, 25 ms são seis ciclos e meio, e o ouvido
    # lê isso como um estalo sem altura em vez de uma nota.
    yield "toque", sino("C4", 0.045, decaimento=8.0, harmonicos=(1.0, 0.12))

    # Pip da contagem 3-2-1. Tocado com pitch_scale crescente pelo chamador
    # (1.0 / 1.12 / 1.26), então o topo da contagem chega a ~415 Hz — bem
    # dentro da faixa que o alto-falante do celular reproduz inteira.
    yield "contagem", sino("E4", 0.16, decaimento=5.5)

    # "Comece agora". Duas notas subindo — a segunda cai exatamente no
    # instante em que a barra de captura começa a encher.
    yield "gravar", sequencia([
        (0.00, sino("G4", 0.18, decaimento=6.5, sub=0.20)),
        (0.08, sino("D5", 0.34, decaimento=5.0, sub=0.20)),
    ])

    # Fim da captura: mesmo par, descendo. Diz "pode baixar as mãos" sem
    # sugerir acerto nem erro — a nota ainda nem foi calculada.
    yield "captura_fim", sequencia([
        (0.00, sino("D5", 0.16, decaimento=6.5, sub=0.20)),
        (0.08, sino("G4", 0.38, decaimento=4.5, sub=0.25)),
    ])

    # Uma estrela. O chamador toca até três, em pitch 1.0 / 1.26 / 1.5, o que
    # monta um dó maior (523 / 659 / 785 Hz). Cauda longa de propósito: é a
    # recompensa, e é onde a sub-oitava mais rende.
    yield "estrela", sino("C5", 0.62, decaimento=4.0,
                          harmonicos=(1.0, 0.28, 0.10, 0.04), sub=0.30)

    # XP creditado. É o som mais agudo que sobrou, e continua sendo: ele cai
    # em cima da cauda das estrelas e precisa de um registro próprio para não
    # sumir dentro delas.
    yield "xp", sequencia([
        (0.00, sino("E5", 0.12, decaimento=7.0, harmonicos=(1.0, 0.20))),
        (0.07, sino("A5", 0.28, decaimento=5.5, harmonicos=(1.0, 0.20))),
    ])

    # Zero estrelas. Duas notas descendo, sem dissonância: o app está pedindo
    # outra tentativa, não repreendendo ninguém. Grave e redondo cai bem aqui.
    yield "tentar_de_novo", sequencia([
        (0.00, sino("D4", 0.20, decaimento=5.0, harmonicos=(1.0, 0.15))),
        (0.13, sino("C4", 0.46, decaimento=4.0, harmonicos=(1.0, 0.15), sub=0.25)),
    ])

    # "Não deu para avaliar" — falha técnica (usuário fora do quadro, captura
    # vazia). Fosco e sem melodia: não é uma nota baixa, é ausência de nota.
    #
    # É o som mais grave do conjunto (G3 = 196 Hz), abaixo do que o alto-falante
    # de um celular emite. O 2º harmônico entra pesado justamente por isso: o
    # ouvido reconstrói a fundamental a partir dele.
    yield "falha", sequencia([
        (0.00, sino("G3", 0.16, decaimento=9.0, harmonicos=(1.0, 0.55, 0.18))),
        (0.11, sino("G3", 0.28, decaimento=9.0, harmonicos=(1.0, 0.55, 0.18))),
    ])

    # Lição concluída: arpejo de dó maior fechando na oitava, com uma
    # fundamental grave sustentando por baixo do acorde.
    yield "licao_concluida", sequencia([
        (0.00, sino("C5", 0.22, decaimento=7.0)),
        (0.10, sino("E5", 0.22, decaimento=7.0)),
        (0.20, sino("G5", 0.26, decaimento=6.0)),
        (0.31, sino("C6", 0.70, decaimento=4.0, harmonicos=(1.0, 0.30, 0.12, 0.05))),
        (0.31, sino("C4", 0.75, decaimento=3.5, ganho=0.55)),
    ])

    # Nível novo. Acontece a cada 500 XP, bem mais raro que uma lição — pode
    # ser o som mais longo e mais cheio do app sem cansar. Duas vozes graves
    # (a tônica e a quinta) seguram o acorde final.
    yield "nivel", sequencia([
        (0.00, sino("G4", 0.20, decaimento=7.0)),
        (0.09, sino("C5", 0.20, decaimento=7.0)),
        (0.18, sino("E5", 0.22, decaimento=6.0)),
        (0.27, sino("G5", 0.26, decaimento=5.5)),
        (0.38, sino("C6", 0.78, decaimento=3.6, harmonicos=(1.0, 0.34, 0.14, 0.06))),
        (0.38, sino("C4", 0.82, decaimento=3.2, ganho=0.60)),
        (0.38, sino("G4", 0.82, decaimento=3.2, ganho=0.40)),
    ])


def main():
    DESTINO.mkdir(parents=True, exist_ok=True)
    print("Gerando efeitos sonoros em %s" % DESTINO)
    for nome, amostras in sons():
        escrever(nome, amostras)
    print("Pronto. Reimporte no Godot: godot --headless --import --quit")


if __name__ == "__main__":
    main()
