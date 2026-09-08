# Modo debug

Um painel dentro do próprio app, para exercitar telas e estados sem percorrer
o fluxo inteiro. Abre pela alça `D` na borda esquerda da tela.

## Por que ele existe

Chegar na tela de resultado custava: abrir o app, escolher a lição, ver o
avatar, esperar a contagem, executar o sinal na frente da câmera, esperar de 1
a 8 s de análise — e ainda assim **sem controle sobre a nota que ia sair**.
Testar 0 estrelas exigia errar de propósito. Testar "não vimos suas mãos"
exigia sair do quadro na hora certa. Testar o mapa com lições concluídas
exigia concluí-las.

E o alvo é o celular, onde não há editor nem depurador à mão — é lá que a
câmera, o backend de inferência e o alto-falante se comportam de verdade. Um
atalho que só funcionasse no editor resolveria o problema no lugar errado.

## O que ele faz

**Etapa da lição** — pula direto para observar o sinal ou para a gravação.
Só funciona com uma `LessonScreen` na cena; fora dela o painel diz isso em vez
de não fazer nada.

**Resultado sintético** — um slider de precisão (com a nota prevista ao lado) e
atalhos para as faixas de 0 a 3 estrelas, mais os três casos que são difíceis
de reproduzir de propósito com uma câmera na mão:

| Botão | Reproduz |
|---|---|
| `Sem mãos` | grupos exigidos e nunca detectados → título "Não vimos suas mãos" |
| `Falha` | a validação nem roda → "Não deu para avaliar" |
| `Espelhado` | execução canhota reconhecida → a nota explicativa no detalhamento |

O `DebugValidator` imita o retorno do `MotionComparatorValidator` campo a
campo, incluindo o `details` por grupo com notas propositalmente diferentes
entre si — assim o detalhamento e a frase de orientação do "pior parâmetro"
são exercitados de verdade, não só o número grande.

**Progresso** — `+100 XP`, `+1 nível`, `Concluir todas` (que também destrava
tudo: o desbloqueio é derivado de "a anterior está completa", não é um campo
próprio) e `Zerar tudo`.

**Diagnóstico** — aparelho, versão, fps da UI, memória, som, backend preferido
→ resolvido, threads, estado da GPU, lição/sinal atual, câmera, e os números
da inferência (entrada, resultados, latência, readback, tamanho do quadro).
São os mesmos da linha `[perf]` do log, agora retidos em
`HolisticLandmarker.last_perf` para poderem ser mostrados. É o que responde
"a GPU pegou neste aparelho?" sem cabo e sem `logcat`.

## As duas garantias

**1. Não vaza para a build final.** `Debug._ready` retorna imediatamente
quando `OS.is_debug_build()` é falso: sem CanvasLayer, sem alça, sem
`_process`. Numa build de release não existe nada para tocar.

**2. Não corrompe dados.** Todo resultado do `DebugValidator` carrega
`_debug: true`, e `FeedbackState._fill_reward` para nessa flag: **nenhum XP é
creditado e nada conta como prática**. A ofensiva e a precisão média são
números que o trabalho cita — enchê-los de notas inventadas durante um teste
de UI os invalidaria sem deixar rastro. A tela mostra "RESULTADO SINTÉTICO"
no lugar do chip de XP.

E a garantia mais importante, porque o defeito seria invisível: `Debug.injetar`
troca o validator, dispara a avaliação e **devolve o original**, sempre. Deixar
o falso instalado faria a próxima gravação de verdade produzir uma nota
inventada, indistinguível de uma real. É a única parte do painel que é estática
e isolada num método só — para poder ser testada sem montar uma lição inteira.

## Um defeito que ele revelou

Escrever o teste de integração do painel derrubou a suíte com `SIGABRT` **depois**
de ela reportar sucesso. Isolando: um `WorkerThreadPool.add_task` puro, sem
nada deste projeto, aborta no encerramento do processo se o id da tarefa nunca
for passado a `wait_for_task_completion`.

`FeedbackState.evaluate` descartava esse id desde o Sprint 2. Cada gravação
avaliada prendia uma vaga do pool para sempre. Nunca apareceu porque só se
manifesta na saída do processo — o app fecha e ninguém vê.

Corrigido: o id é guardado por geração e recolhido na entrega do resultado
(`_reap_task`), onde a tarefa já terminou e a espera retorna na hora. Uma
análise ainda em andamento na hora de sair da tela é deixada de lado de
propósito — esperar por ela bloquearia a troca de cena por até 8 segundos, e
quem apertou "voltar" no meio da análise é exatamente quem não pode ficar
preso. `tests/unit/test_feedback_stars.gd` vigia a invariante.
