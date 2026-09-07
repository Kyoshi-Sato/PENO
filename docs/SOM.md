# Som

Nada no app dependia de áudio até aqui. Este documento registra o que foi
acrescentado, onde, e as duas decisões que não são óbvias.

## A regra que restringe todo o resto

Este é um app de LIBRAS. Parte do público-alvo não vai ouvir nada.

Então: **nenhum som carrega informação que não esteja na tela.** Não é uma
formalidade de acessibilidade — é o critério que decidiu quais momentos foram
sonorizados e quais não foram. Todo cue abaixo dobra um elemento visual que já
existia antes dele:

| Som | O que ele dobra na tela |
|---|---|
| toque | o botão encolhe (`Motion.attach_press`) |
| contagem | o numeral 3/2/1 pulsando |
| gravar | a barra de captura começa a encher |
| captura_fim | a barra some e o texto vira "Analisando seu sinal…" |
| estrela | cada estrela entra na `StarRow` |
| xp | o chip "+N XP" |
| tentar_de_novo | título "Vamos tentar de novo?" e o anel em 0 estrelas |
| falha | título "Não deu para avaliar" / o card travado tremendo |
| licao_concluida | a volta ao mapa com a lição marcada |
| nivel | o nível no cabeçalho da Home |

Com o som desligado o app continua completo. É por isso que ele pode vir
ligado por padrão sem esconder nada de ninguém — e a chave está em
Configurações, no primeiro cartão.

## Por que os arquivos são sintetizados

`tools/gerar_sons.py` gera os dez WAVs com a biblioteca padrão do Python.
Nenhum arquivo de origem externa entra no repositório.

O motivo é procedência: um trabalho acadêmico não pode versionar um WAV de
licença desconhecida. Aqui cada som é uma função determinística de um arquivo
de 200 linhas, reproduzível byte a byte com

```
python3 tools/gerar_sons.py
godot --headless --import --quit
```

O efeito colateral útil é que o timbre inteiro é uma decisão editável: as notas
saem de uma escala de dó maior, então dois sons que se sobreponham na tela de
resultado continuam consoantes. As três estrelas são **um arquivo só**
transposto em 1.0 / 1.26 / 1.5 — dó, mi, sol. Três estrelas fecham o acorde;
uma estrela soa como começo de frase.

## O registro, e por que ele não desce mais

A primeira versão vivia entre C5 e C7 (523 a 2093 Hz) e soava estridente. A
atual desceu uma oitava — mas **não mais do que isso**, e o limite é físico:

> o alto-falante de um celular só começa a responder por volta de 400 Hz, cai
> uns 10 dB em 300 Hz e praticamente não emite nada abaixo de 200 Hz.

Descer além disso não deixa o som mais grave; deixa ele inaudível no único
aparelho que importa. As fundamentais ficaram entre 196 e 1046 Hz, com a maior
parte do peso entre 260 e 780.

A profundidade que faltava veio de três lugares que não custam registro:

1. **menos conteúdo agudo** — o peso do 2º e do 3º harmônico caiu de 0,32/0,12
   para 0,22/0,06;
2. **os agudos morrendo antes da fundamental** (`AMORTECIMENTO_HARMONICO`),
   que é o que o ouvido lê como "abafado" — um instrumento real perde o brilho
   antes de perder o corpo;
3. **decaimento mais lento** — cauda longa soa como corpo, não como tique.

Isso é mensurável e foi medido. No som de estrela, que é o mais ouvido da tela
de resultado, a fundamental caiu 50% e o **centroide espectral caiu 60%**
(1168 → 464 Hz): o timbre escureceu além do que a simples transposição
explicaria, que era exatamente o objetivo.

Uma exceção deliberada: o som de falha está em G3 (196 Hz), abaixo do que o
alto-falante emite. O 2º harmônico entra pesado de propósito — o ouvido
reconstrói a fundamental ausente a partir dele, e o som continua lendo como
grave num alto-falante que não consegue produzi-lo.

Os ganhos em `Audio.CUES` subiram 2 dB em bloco junto com a mudança. Não é
gosto: som grave com a mesma amplitude é percebido como mais baixo (curvas de
igual sonoridade), e o alto-falante atenua a região por conta própria. O
equilíbrio relativo entre os dez sons não mudou.

## Onde o código está

- `Scripts/autoload/Audio.gd` — autoload `Audio`. Tabela de cues (arquivo +
  ganho), seis vozes num barramento `SFX` próprio, `play()` e `play_cascade()`.
  Falha silenciosa por decisão: um efeito que não carregou avisa uma vez em
  `push_warning` e o app segue mudo naquele som, nunca quebra a tela.
- `Global.is_sound_enabled()` / `set_sound_enabled()` — preferência **do
  aparelho**, em `user://settings.json`, ao lado da escolha de GPU/CPU e
  portanto fora do alcance de "Apagar dados".
- `default_bus_layout.tres` — o barramento `SFX`. Existe para o volume dos
  efeitos ser ajustável sem tocar no Master, que é onde a captura de áudio do
  GDMP também vive.

## As duas armadilhas

**1. Os WAVs são carregados por caminho montado em runtime.** O rastreador de
dependências do exportador não os enxerga. Eles entram no APK porque os presets
usam `export_filter="all_resources"`. Se isso um dia virar `resources from
scenes`, os sons somem do build **sem nenhum erro de compilação**.
`tests/unit/test_audio.gd` é o único lugar do projeto que verifica essa
ligação — ele falha se um arquivo sumir, for renomeado ou deixar de importar.

**2. `Motion.attach_press` e `LessonNode` são chamados por componentes
`@tool`.** Numa sessão do editor o autoload `Audio` não existe. As duas
chamadas são guardadas por `Engine.is_editor_hint()`.

## O que deliberadamente ficou mudo

- **A troca de tela e a navegação.** O toque no botão já soou; um segundo som
  na chegada da tela seria eco.
- **A análise em andamento.** São 1 a 8 segundos; qualquer som de espera vira
  incômodo antes de virar informação.
- **O avatar executando o sinal.** Um som ali sugeriria que o gesto tem áudio,
  e ele não tem.
