# PENO — Revisão Técnica Completa (Fases 1–4)

**Data:** 2026-07-19 · **Escopo:** todo o repositório exceto o interior de `addons/` (código de terceiros) e binários de assets.
**Método:** leitura integral dos arquivos do núcleo + 6 investigações paralelas especializadas (algoritmo de CV, robustez de CV, arquitetura, performance, práticas Godot/testes, qualidade) com verificação adversarial cruzada. Toda afirmação abaixo tem citação `arquivo:linha` verificada.

---

## Sumário executivo

O projeto tem um esqueleto defensável — fluxo de estados limpo (Showcase → Recording → Feedback), uma seam de validador injetável (`SignValidator`), e um vocabulário de features geometricamente razoável (vetores unitários por osso, normal da palma, direção da mão, segmentação por velocidade). **Mas as três alegações centrais do app estão quebradas de ponta a ponta no build atual:**

1. **O APK não consegue abrir a câmera** na única plataforma-alvo (`export_presets.cfg:111` tem `permissions/camera=false` e não há request de permissão em runtime para Android).
2. **A validação não valida.** O DTW anunciado no docstring é computado e **descartado** — a nota real vem de comparação quadro-a-quadro por índice entre gravações de fps diferentes. Dados ausentes são silenciosamente excluídos em vez de penalizados: um usuário **parado, com as mãos escondidas, tira 1–2 estrelas**, enquanto um sinal correto executado 0,5 s atrasado pode tirar nota **pior**. A discriminação está parcialmente invertida.
3. **A nota não conta.** `LessonScreen.gd:278` persiste `mark_completed(id, 3)` — 3 estrelas fixas, qualquer que seja o desempenho. E a seleção de lição está travada na lição 1 por dois bugs que se mascaram mutuamente (`debug_lesson_id = 1` + catálogo emitindo `id_exercicio` enquanto todos os consumidores leem `id`).

Nenhum desses problemas exige ML ou pesquisa nova — todos têm correção determinística conhecida, a maioria pequena. A boa notícia acadêmica: o núcleo (`Comparador.gd`) é um `RefCounted` puro, 100% testável sem câmera nem cena, e o caminho até um método defensável em banca/publicação (DTW multivariado com banda + normalização espacial + calibração por sinal com dataset rotulado) está inteiramente dentro do escopo de um TCC.

---

# Fase 1 — Modelo do repositório

## Stack e configuração

- **Godot 4.6** (projeto) rodando em engine 4.7 local; renderer `mobile` com feature tag `"GL Compatibility"` contraditória (`project.godot:19`); portrait 1080×1920; alvo Android (CI exporta APK).
- **Não há Python no repositório.** MediaPipe roda via **GDMP** (GDExtension em `addons/GDMP`, ~300 MB de binários para 6 plataformas). `CameraServerExtension` enumera câmeras e pede permissão (mas só em Windows/iOS — `VisionTask.gd:173-177`).
- **Autoloads:** `MediaPipeExternalFiles`, `GDMPAndroid`, `Global` (progresso + navegação + download de modelos), `LessonService` (API remota).
- **Cena principal:** `GUI/Screens/Main/Main.tscn` (confirmado por uid `c5lpjegcml0ma`). Todo o conjunto `GUI/Screens/Screen Scripts/*` + `MainMenu/LearningMap/PlayerStats` é **legado inalcançável** (MainMenu.tscn referencia `res://R.jpeg` que nem existe).

## Fluxo de dados

```
Main.tscn / LessonMapScreen ──Global.go_to_lesson(id)──► LessonScreen
                                                            │
   LessonService ──HTTP──► api.ciclicainteractive.com       │
   (api_key hardcoded)     lesson = { nome_sinal,           │
                                      anim_lib (.tres),     │
                                      json_sinal (gabarito)}│
                                                            ▼
        SignShowcase ──► RecordingState ──► FeedbackState
        (avatar toca      (countdown +       (validate → estrelas)
         anim .tres)       captura)
```

**Pipeline de captura (por frame de câmera):**
`CameraServer feed → CameraTexture → SubViewport` (com `flip_h = true` se câmera frontal + correção de rotação, `VisionTask.gd:230-233, 304-311`) `→ await frame_post_draw → get_image()` (**readback GPU→CPU síncrono, ~2,7 MB/frame a 720p**, `VisionTask.gd:313-331`) `→ MediaPipe Holistic (live stream) → _packets_callback` (**thread de worker do GDMP**) `→ _collect_frame` (pose 33 + 2×21 mãos, com `visibility/presence` serializados mas nunca consumidos) `→ _export_capture_json` (grava `user://anim_cache/holistic_capture_<ts>.json`, 3–8 MB) `→ landmarks_detected(payload) → FeedbackState`.

**Pipeline de validação (`Comparador.gd`, 1.188 linhas, classe `MotionComparator`):**
1. Por **grupo** (pose, mão esquerda, mão direita) e por **osso** (pares de landmarks em `POSE_BONES`/`HAND_BONES_*`): vetor unitário do osso em coordenadas normalizadas de imagem (`bone_vector`, :191-200).
2. Diferença angular **quadro i vs. quadro i** (`series_to_angle_diff`, :397-408, truncado ao menor comprimento) → `angle_to_similarity` exponencial (steepness 2/3/3,5, :216-218) → média ponderada por `BONE_WEIGHTS` e pesos de repouso.
3. Um DTW 100×100 por osso é computado (:812) e **guardado sem uso** (:823).
4. Mãos: mistura com "fase" (:846-852), depois **sobrescrita** (:913) por recomputação palma (peso 3,5) + direção (peso 4,0).
5. Fase: segmentação por velocidade (limiar `max(1,2×mediana, 0,01)`, :627), pareamento de segmentos **por índice** (:685), DTW 1-D usando **só o componente x de um osso proxy** (:747, :805-808).
6. Global: média ponderada dos grupos **excluindo NANs** (:927-931) → `_global_similarity_pct` → `precision` → estrelas (0,9/0,7/0,5 em `FeedbackState.gd:120-127`).

---

# Fase 2 — Revisão de engenharia holística

## Corretude — a cadeia principal está quebrada em pontos independentes

| # | Defeito | Evidência |
|---|---|---|
| C1 | **Export Android sem permissão de câmera**; request runtime só em Windows/iOS. APK de CI = tela preta, 0 frames. | `export_presets.cfg:111`; `VisionTask.gd:173-177` |
| C2 | **Contrato do catálogo quebrado:** serviço normaliza para `id_exercicio`/`nome_exercicio`, todos os consumidores leem `id` → toda lição vira `-1`, `is_unlocked(-1)` destrava tudo. O `DEBUG_CATALOG` usa `id` — por isso funcionava em debug. | `LessonService.gd:246-250` vs `Main.gd:112,222`, `LessonMapScreen.gd:64`, `Global.gd:140-146` |
| C3 | **`debug_lesson_id = 1` vence sempre** (só lê `Global.current_lesson_id` se `< 0`) → app cravado na lição 1 em qualquer build; mascara C2. | `LessonScreen.gd:13,75-77` |
| C4 | **3 estrelas fixas persistidas** independentemente da nota; as estrelas reais morrem dentro do FeedbackState. Progressão avança com 0 estrela. | `LessonScreen.gd:278`; `Global.gd:151` |
| C5 | **Cancelar no meio da gravação mata a câmera para o resto da sessão** (`_reset` desativa o feed; nada reativa). Abrir engrenagem durante captura também deixa o RecordingState preso em RECORDING para sempre (timer parado, sem timeout). | `VisionTask.gd:82-88`; `HolisticLandmarker.gd:51-58,111` |
| C6 | **Botões do feedback errados:** "Ver módulos" emite `retry_requested` (refaz o sinal); não existe caminho para o mapa; "Tentativas" sempre = 1; título sempre "Parabéns!" mesmo com 0 estrela ou erro de validação. | `FeedbackState.gd:43,37,63-64` |
| C7 | **Race condition:** `_packets_callback` roda na thread do GDMP e faz append em `capture_frames` sem mutex, enquanto a main thread limpa (`_reset`) e lê (`_export_capture_json`) o mesmo Array. | `HolisticLandmarker.gd:277,335-370` |
| C8 | Sinal `landmarks_detected` declarado **sem parâmetros** mas emitido com payload; funciona hoje (verificado empiricamente em 4.7), mas viola o contrato e quebra checagem estática. | `HolisticLandmarker.gd:19,502` |

## Performance (alvo: Android mid-range)

| # | Defeito | Custo estimado |
|---|---|---|
| P1 | **Validação inteira síncrona na main thread** ao entrar no Feedback. | **2–8 s de UI congelada** — território de ANR |
| P2 | **45 DTWs 100×100 computados e descartados** (≈450 mil células). | ~40–55 % do custo de P1: **1–5 s de trabalho morto** |
| P3 | `get_landmark` é varredura O(n) chamada ~54 mil vezes por validação (~700 mil iterações) sobre dados já indexáveis por id. | ~0,3–1 s |
| P4 | **Readback GPU→CPU por frame de câmera** (SubViewport 720p, `render_target_update_mode = ALWAYS`). | 12–30 ms/frame na main thread |
| P5 | **Câmera + inferência Holistic rodam em todos os estados** (Showcase, Feedback) com resultados jogados fora; feed nunca desativado ao concluir a lição. | bateria + GPU/CPU contínuos |
| P6 | Dump JSON de 3–8 MB com indentação, síncrono, a cada captura; `anim_cache` cresce sem limite (`clear_cache()` existe e nunca é chamado). | hitch + storage infinito |
| P7 | SubViewports do avatar em `UPDATE_ALWAYS` renderizam 3D em full-res mesmo cobertos pela UI de gravação. | GPU desperdiçada |
| P8 | Mediana por insertion-sort O(n²), overlay = segundo passe MediaPipe síncrono, ~75 Dictionaries alocados por frame. | menores, mas somam |

**Pilha de correção estimada:** deletar P2 (−1 a −5 s) + indexar landmarks (−0,3 a −1 s) + velocidades em passada única, depois mover `analyze_similarity` para `WorkerThreadPool` → **zero congelamento percebido**, sem mudar nenhum resultado numérico.

## Segurança

- **RCE:** `LessonService._load_animation_from_tres_text` grava texto vindo da API em disco e carrega via `ResourceLoader` (`LessonService.gd:172-181`). Um `.tres` pode embutir script — API comprometida (ou MITM) = execução arbitrária de código no dispositivo do aluno.
- **API key `"chave_secreta_godot"` commitada em dois arquivos** (`LessonService.gd:35`, `testerequest.gd:5`) e extraível do APK (export mode 2 mantém strings). `testerequest.gd` ainda é `@tool` e dispara requisição HTTP real ao abrir a cena no editor.

## Práticas Godot e arquitetura

- O sensor de produção **é o Control de demo do GDMP quase intacto** (`VisionTask.gd`), instanciado invisível dentro do LessonScreen e dirigido por **métodos privados com duck-typing** (`holistic._begin_capture(...)`, `_reset()`, 9 checagens `has_method`/`has_signal` — `LessonScreen.gd:57-64,104-152,225`). Um método renomeado silenciaria a gravação sem erro. Os 18 nós de UI de demo continuam carregados e com handlers vivos. Bônus: os shaders são carregados de `res://vision/*.gdshader` (`VisionTask.gd:278,293`) — caminho que não existe fora do addon (o real é `res://GUI/vision/`).
- `LessonStateMachine` (36 linhas) é um relay de sinais: o enum de estado nunca é lido, não há guarda de transição. Colapsar num enum + método dentro do LessonScreen é deleção líquida de código.
- **Caminho profundo hardcoded no rig:** `$AvatarViewportContainer/AvatarViewport/Avatar/Libra2/Armature_002/AnimationPlayer` (`LessonScreen.gd:24`) — o próximo re-export do Blender (`Armature_003`) quebra tudo silenciosamente.
- **Construtor do mapa de lições copiado verbatim** entre `Main.gd:202-249` e `LessonMapScreen.gd:20-91` (e uma 3ª cópia no legado morto); `ModuleButton.tscn` existe e ninguém usa. O bug C2 precisa ser corrigido em dois lugares.
- **UI fantasma:** PrecisionRing fixo em 0.0 e checklist sempre "pending" (`RecordingState.gd:109-112`); `frame_instant_similarity` (`Comparador.gd:967-1031`) foi claramente escrito para alimentá-los e tem **zero chamadores**. Preview anotado **duplamente espelhado** (flip no viewport + flip no TextureRect) → o overlay mostra o mundo invertido em relação ao preview cru, e alternar o "olho" flipa a imagem (`RecordingState.gd:87` + `VisionTask.gd:230-233`).
- `Themecreator.gd` é `@tool` e **regrava `res://themes/libras_soft.tres` toda vez que `node.tscn` é aberto no editor** — clobbering silencioso de um recurso commitado.

## Higiene de repositório e CI

- **665 MB:** 300 MB de binários GDMP para 6 plataformas (só Android arm64 é distribuído), `.git` de 257 MB carregando um `Main.tscn` deletado de **88 MB**, ~200 MB de histórico de `MACACAREFA.blend`, e um modelo **"Yor Forger" (Spy×Family) ripado** no histórico — bandeira real de licenciamento para publicação.
- Lixo na raiz: `node.tscn` + `.tmp`, `resqueteste.tscn`, `teste_4597.gd` (referencia `res://data/` inexistente), `Untitled.png`, `Sem título.png`, `.blend1`, fragmentos `.yml` órfãos.
- **CI:** lint com `continue-on-error: true` (teatro puro); release dispara em **todo push na main** apesar do comentário "só em tags"; instala .NET para um projeto sem um único `.cs`; **não existe job de teste**.
- **Zero testes. GUT nem está instalado** — `gut.conf` aponta para `res://tests` inexistente. Nenhum README.

---

# Fase 3 — Revisão profunda da validação gestual

## 3.1 O que a nota realmente mede (vs. o que o código alega)

O docstring de `Comparador.gd:6-10` promete alinhamento temporal por DTW. Na prática:

1. **O termo dominante da nota é comparação por índice de frame** (:815-819): frame *i* do usuário vs. frame *i* do gabarito, truncado ao menor. Como o Holistic mobile roda a ~10–20 fps e o gabarito offline a ~30 fps, "frame i" de cada lado é um instante de parede diferente — **a métrica mede desvio de timing, não erro de gesto**. Um usuário que reage 0,5–1 s após o "Vai!" (latência humana normal; a janela é só `duração_anim + 1 s`, `LessonScreen.gd:11`) tem o sinal inteiro defasado → diffs angulares explodem nas transições → 0–1 estrela para uma execução correta.
2. **O DTW por osso (:812) é guardado em `bone_results` (:823) e nenhum scorer o lê** (verificado por busca exaustiva: único consumidor é `print_summary`). É só custo (ver P2).
3. **Dado ausente = dado excluído, nunca penalizado.** Grupos NAN saem da média global (:927-931); fase NAN é pulada (:847); a penalidade de cobertura (:710-712) só dispara se existir ≥1 par de segmentos.
4. **Trace do usuário imóvel** (confirmado independentemente por dois especialistas): velocidade ≈ jitter → 0 segmentos → `n_pairs = 0` → fase NAN → pulada sem penalidade; mãos escondidas → grupos de mão NAN → excluídos; sobra **postura estática de torso/pernas vs. a pose de descanso do sinalizador de referência ≈ 90–95 % por osso** → global **~60–80 % = 1–2 estrelas por não fazer nada**. Combinado com o item 1: **ficar parado pontua melhor do que sinalizar corretamente com atraso.**
5. **Sobrescrita da fase nas mãos:** o blend de :846-852 é destruído em :913 pela recomputação palma/direção — o único componente genuinamente temporal da nota fica quase inaudível (peso 1,5 vs. ~20–27 do grupo) *e* parcialmente sobrescrito. É um bug real, de efeito pequeno só por acidente de pesos.
6. **A "fase" opera em 1-D:** só o componente **x** de **um osso proxy** (`bones[0]` = `thumb_L_1` para mãos, `spine` para pose — :682,:747) representa o segmento inteiro no DTW. Cega a movimento vertical e de profundidade; e x é exatamente o eixo corrompido pelo espelhamento (abaixo). `_nan_to_zero` (:506-508) ainda injeta zeros fabricados (x=0 é uma direção válida!) nas sequências.

## 3.2 Sistemas de coordenadas, espelhamento e lateralidade

- **Contrato de quiralidade violado no caminho padrão:** câmera frontal → SubViewport com `flip_h = true` → **MediaPipe recebe imagem espelhada** (`VisionTask.gd:230-233`). O Holistic deriva o lado da mão pela pose (aparência), então a mão física direita cai no stream LEFT → rotulada "Left" (`HolisticLandmarker.gd:347-353`, confiança hardcoded 1.0). O gabarito offline (vídeo não espelhado, convenção do MediaPipe não corrigida) rotula a mão física direita de "Left" **também** — os rótulos coincidem por acaso de duas convenções opostas, mas a **geometria fica espelhada**: componentes x negados entre usuário e gabarito. Sob reflexão, a normal da palma vira (nx,−ny,−nz): **palma voltada para a câmera compara ~180° errada na feature de maior peso das mãos** (palma 3,5; direção 4,0 também flipa para qualquer apontar horizontal). Câmera traseira (`flip_h = false`) inverte a convenção de novo — **a nota muda silenciosamente conforme a câmera escolhida** no diálogo de configurações.
- **Anisotropia de aspecto:** `bone_vector` usa coordenadas normalizadas de imagem cruas (x=px/W, y=px/H, z pseudo-profundidade em outra escala). Gabarito 16:9 vs. formato da câmera ao vivo ≠ → erro angular sistemático em **todos** os ossos. Sem Procrustes/alinhamento rígido, um celular inclinado 20° soma ~20° a quase todo diff — a steepness 3 isso custa ~30 pontos globais.
- **Canhotos não existem para o app:** matching estrito de rótulo Left↔Right (:356-374). Sinalizadores canhotos (espelhamento fonologicamente legítimo em LIBRAS, ~10 % dos usuários) têm a mão dominante comparada contra a mão em repouso do gabarito → NAN (excluído) ou ~0. Falha dura de acessibilidade num app de ensino de língua de sinais.

## 3.3 Robustez temporal

- **Nenhuma suavização de landmarks em lugar nenhum** (verificado por grep + leitura): o único smoothing do repositório é a média móvel janela-5 sobre o sinal de velocidade da segmentação (:590-604,:619). A normal da palma — produto vetorial de 3 pontos vizinhos — é **amplificadora de jitter** e entra crua com peso 3,5.
- **Segmentação frágil:** limiar `max(1,2×mediana, 0,01)` com piso absoluto em unidades normalizadas (usuário longe → velocidade sub-piso → 0 segmentos → fase some); dropouts de detecção zeram a velocidade (:564-565) e fabricam fronteiras de segmento; o movimento de abaixar o braço pós-toque vira "segmento #1" do usuário e é pareado **por índice** contra o sinal real do gabarito.
- **Sem piso de cobertura:** uma mão detectada em 5 de 300 frames pontua com peso cheio a partir desses 5 frames (:537-548); `visibility/presence` são capturados (`HolisticLandmarker.gd:441-449`) e ignorados por todos os leitores. A nota é **descontínua** na qualidade de detecção: 0 frames = grupo excluído; 3 frames = grupo conta inteiro.
- **Sem validação de schema do gabarito:** `_ensure_doc_shape` só preenche fps ausente (`MotionWrapper.gd:43-55`). Gabarito sem `pose`, com convenção de mão diferente, z em outra escala ou fps=0 **não falha — produz nota confiantemente errada** (e se o gabarito for só-mãos, a LOCALIZAÇÃO do sinal — parâmetro fonológico central de LIBRAS — nunca é avaliada, invisivelmente).

## 3.4 Calibração

Um único mapeamento global 0,9/0,7/0,5 → 3/2/1 estrelas para todos os sinais. Com steepness 3: erro uniforme de 30° = 57,9 % (1 estrela quase de graça, ajudado pela exclusão de NAN); **3 estrelas exige erro médio ≤ 6,2° — abaixo do piso de ruído do próprio MediaPipe** somado às distorções de aspecto/viewpoint. Todas as constantes (steepness {2, 3, 3,5}, pesos palma 3,5/direção 4,0/fase 1,5, `BONE_WEIGHTS`) são ajustadas à mão, sem dataset, sem ROC, sem thresholds por sinal em lugar algum (nem no payload da API). Pares mínimos de um dedo movem o grupo de mão ~9–10 pontos — letras confundíveis passam juntas.

## 3.5 Comparação com a literatura (técnicas determinísticas)

| Estágio | PENO hoje | Prática padrão determinística | Esforço |
|---|---|---|---|
| Alinhamento temporal | Índice de frame; DTW morto sem caminho | **DTW multivariado único** (vetor de ângulos concatenado, custo local L2 ponderado) com **banda Sakoe-Chiba ~10–20 %**, nota = erro médio por osso **ao longo do caminho ótimo** (exige backtracking, que hoje não existe) | ~150 linhas |
| Normalização espacial | Coordenadas de imagem normalizadas + pseudo-z | **World landmarks** do MediaPipe (métricos, independentes de aspecto/distância — só religar streams em `HolisticLandmarker.gd:238-241`) e/ou **Procrustes por frame** (Kabsch fechado no quadro ombro-quadril, ~40 linhas) | pequeno |
| Filtragem | Nenhuma | **One-Euro** (Casiez et al. 2012) por landmark — padrão de facto na frente do MediaPipe; ~20 linhas, lag sub-frame; estabiliza sobretudo a normal da palma | pequeno |
| Segmentação | Limiar de mediana + pareamento por índice | **Trimming de repouso por velocidade nas pontas** + DTW banded na sequência inteira (mais simples e melhor aqui); se mantiver segmentos, **segmental DTW** (pareamento por melhor match) | pequeno–médio |
| Template | 1 gravação de referência | **DBA** — DTW Barycenter Averaging (Petitjean 2011) sobre 5–10 takes do professor → template robusto **+ distribuição intra-classe de graça** | médio (mais coleta) |
| Thresholds | Globais 0,5/0,7/0,9 | **Percentis por sinal** da distribuição mesmo-sinal vs. distratores; reportar **EER/ROC/matriz de confusão** — o mínimo que um revisor exige para a alegação "o app valida sinais" | médio (coleta) |
| Família $1/$P/$P+ | — | Invariante a rotação/escala e minúsculo, mas é classificador de **forma 2D** que descarta dinâmica temporal e estrutura por junta → serve no máximo como checagem secundária barata da trajetória do pulso, **não** como validador principal | n/a |

**Veredito sobre ML:** não se justifica. Vocabulário pequeno, tarefa de *verificação* por sinal (não classificação aberta), necessidade de interpretabilidade por osso para feedback pedagógico, e execução determinística on-device — o pipeline DTW+calibração acima é o estado da prática para exatamente este problema e mantém a restrição de determinismo do projeto. Um classificador aprendido só entraria se o vocabulário crescesse a centenas de sinais com usuários abertos, e mesmo então como *rejeitor* na frente do verificador determinístico.

## 3.6 Extensibilidade — "adicionar um sinal com mínimo de código"

**Hoje:** em teoria, adicionar um sinal é 100 % servidor (entrada no catálogo + `.tres` de animação + JSON de gabarito) e zero código no cliente — o design está certo. **Na prática está quebrado por C2+C3** (o cliente nunca sai da lição 1), o gabarito não tem schema validado (3.3), e os thresholds são globais (3.4). **Alvo:** payload por sinal com metadados `{threshold_1/2/3_estrelas, mão_dominante, grupos_relevantes}`; validação de schema na ingestão; uma ferramenta de captura de referência (o exportador JSON já existe — falta empacotar) e o cliente permanece genérico. Com isso, adicionar um sinal = gravar takes + subir; nenhuma linha de GDScript.

## 3.7 Plano de testes (GUT)

`MotionComparator` é `RefCounted` puro — **o artefato mais testável e mais crítico do repositório**, testável com `MotionComparator.new()` sem cena/câmera/autoload.

- **P0 — unit puro (instalar GUT 9.4.x, criar `res://tests/unit`):** `angle_between` (ortogonal=90, paralelo=0, clamp), `angle_to_similarity` (f(0)=100, f(180)=0, monotonia, steepness), `compute_dtw_distance` (idênticas=0, simetria, casos pequenos conhecidos), `normalize_sequence`/`_interpolate_1d` (invariantes de comprimento, endpoints, vazio/1 elemento), `build_rest_weights` (fps=0!), `weighted_mean_angle` (filtro NaN, peso-zero), `smooth_signal`, `detect_gesture_segments` (onda quadrada sintética), medianas par/ímpar, `get_landmark`/`bone_vector`/`palm_normal` (sentinelas INF, ossos degenerados), `_estimate_fps`/`_ensure_doc_shape`.
- **P1 — regressão golden-file:** 4–6 JSONs de captura pequenos commitados em `res://tests/fixtures`; assert `analyze_similarity(X,X) ≈ 100 %`, mesmo-sinal > sinal-diferente, e **pinar o `_global_similarity_pct` exato** como regressão (toda mudança no comparador vira diff visível). Incluir fixtures com mãos ausentes, mão única e fps divergentes (30 vs. 12).
- **P2 — testes de seam:** `FeedbackState.validator` já é injetável — stub de `SignValidator` com precisões fixas → assert fronteiras 0,5/0,7/0,9 e textos; normalização do catálogo com corpos enlatados (**este teste teria pegado C2**); round-trip `Global.mark_completed`/`is_unlocked`.
- **P3 — CI:** job de teste reutilizando o Godot já baixado (`--headless --import` + `gut_cmdln.gd -gexit -gjunit_xml_file`), export dependente dos testes, lint sem `continue-on-error`.
- **P4 — dataset de validação da tese:** K=5 sinalizadores × M=10 sinais × N=5 takes gravados com o próprio app; matriz de similaridade cruzada completa (script de ~50 linhas usando `analyze_similarity`); distribuições mesmo-sinal vs. cruzado → thresholds por percentil → acurácia + matriz de confusão no texto. **Sem isso, os limiares de estrela e o poder discriminativo do comparador são alegações sem suporte.**

Esforço P0+P1: ~2–3 dias.

## 3.8 Lacunas de documentação

Sem README (setup, execução, arquitetura, como gerar gabaritos); sem especificação do formato JSON de captura/gabarito (o contrato central do sistema!); sem documentação da convenção de espelhamento/handedness (3.2 mostra que nem o código a conhece); docstring do Comparador descreve um algoritmo que não é o executado; sem instruções de export/CI; sem licença dos assets.

## 3.9 Avaliação acadêmica

**Forças:** problema socialmente relevante e bem delimitado; escolha determinística correta e defensável; vocabulário de features fonologicamente motivado (configuração de mão via ossos, orientação via palma, movimento via segmentação — mapeia parâmetros de LIBRAS); seam de validador que permite comparar métodos; núcleo puro e testável.
**Fraquezas fatais no estado atual:** o método descrito (DTW) não é o executado; falsos positivos estruturais (usuário imóvel); nenhuma evidência empírica (zero testes, zero dataset, thresholds arbitrários); UI que simula feedback em tempo real inexistente (um avaliador nota); modelo ripado no histórico do git (licenciamento); chave de API commitada. **Nada disso é irrecuperável** — o roadmap abaixo leva o projeto de "demo que aparenta funcionar" a "sistema medido e defensável" dentro do escopo de um TCC.

---

# Fase 4 — Roadmap priorizado

Esforço: P = pequeno (≤ ½ dia), M = médio (½–2 dias), G = grande (> 2 dias).

## CRÍTICO — o app não cumpre a própria função sem isso

| # | Item | Por quê / Impacto | Complexidade | Risco | Esf. |
|---|---|---|---|---|---|
| 1 | **Permissão de câmera Android**: `permissions/camera=true` + `OS.request_permission("CAMERA")` com retry antes da auto-seleção | APK atual não abre câmera na única plataforma-alvo | Trivial | Nenhum | P |
| 2 | **Cadeia de seleção de lição** (juntos, um expõe o outro): normalizar catálogo para `id`/`nome` (`LessonService.gd:246-250`) + `debug_lesson_id = -1` (`LessonScreen.gd:13`) | Multi-lição inacessível; unlock colapsado | Trivial | Baixo | P |
| 3 | **Persistir estrelas reais**: FeedbackState devolve estrelas → LessonScreen agrega (mín. por sinal) → `mark_completed(id, estrelas)`; opcional exigir ≥1 estrela p/ avançar | Hoje a validação não afeta nada — o produto da tese é cosmético | Trivial | Baixo | P |
| 4 | **Penalizar dados ausentes**: grupo estruturalmente ausente = 0 % (ou falha explícita "não vimos suas mãos"); ref. com movimento + usuário sem segmentos → fase = 0 (`Comparador.gd:927,:847,:710`) | Remove o falso positivo dominante (imóvel = 1–2 estrelas) | ~20 linhas | Baixo | P |
| 5 | **Segurança**: eliminar `ResourceLoader` de `.tres` remoto (formato de dados próprio + parser, ou assinatura); tirar a chave do código (injeção em build), **rotacionar a chave**, remover `testerequest.gd` | RCE no dispositivo do aluno; chave pública no APK e no git | M (formato) / P (chave) | Médio | M |

## ALTO — corretude do método e experiência mínima viável

| # | Item | Por quê / Impacto | Complexidade | Risco | Esf. |
|---|---|---|---|---|---|
| 6 | **Contrato de espelhamento**: canonicalizar quiralidade (x→1−x no caminho espelhado, tratamento da normal da palma), documentar convenção, **1 sessão de teste round-trip** app vs. ferramenta offline; câmera traseira idem | Feature de maior peso (palma) compara ~180° errada; nota depende da câmera escolhida | Baixa (código) + 1 sessão empírica | Médio (precisa verificação) | M |
| 7 | **DTW de verdade**: reamostrar por `timestamp_ms`, DTW multivariado único com banda 10–20 % e backtracking, nota ao longo do caminho | Maior ganho de acurácia disponível; absorve fps, atraso de reação e velocidade — converte falsos negativos em acertos | ~150 linhas | Médio (mudar núcleo → golden tests antes!) | M–G |
| 8 | **Descongelar a UI**: deletar DTW morto (:812-823), indexar landmarks por id (O(1)), `WorkerThreadPool` para `analyze_similarity` | 2–8 s de freeze/ANR → 0; −50 % de custo sem mudança numérica | Baixa | Baixo | M |
| 9 | **Ciclo de vida da câmera**: pausar feed+inferência fora do Recording; reativar feed em `_begin_capture` (conserta cancel-mata-câmera); desabilitar engrenagem durante captura ou emitir `capture_aborted`; `call_deferred` na fronteira `_packets_callback` (race) | Bateria, aquecimento, deadlock de gravação, heisenbugs de thread | Baixa–média | Baixo | M |
| 10 | **Normalização espacial**: world landmarks (religar streams) e/ou Procrustes de torso (Kabsch, ~40 linhas) | Remove a maior fonte de erro dependente de ambiente (aspecto + inclinação do celular) | Baixa–média | Baixo | M |
| 11 | **GUT P0+P1 + CI** (plano em 3.7) — **fazer antes do item 7** para pinar comportamento | Pré-condição para mexer no núcleo com segurança; exigência de banca | Baixa | Nenhum | M |
| 12 | **Suporte a canhotos**: rodar comparação também espelhada (x→1−x, troca L/R, flip da palma) e ficar com o máximo | ~10 % dos usuários hoje reprovados por definição, num app de acessibilidade | ~30 linhas | Baixo | P |

## MÉDIO — robustez, calibração e arquitetura

| # | Item | Por quê / Impacto | Complexidade | Risco | Esf. |
|---|---|---|---|---|---|
| 13 | **One-Euro filter** por landmark entre captura e comparação | Estabiliza palma (peso 3,5) e segmentação; omissão que revisor de métodos aponta | ~20 linhas | Baixo | P |
| 14 | **Piso de cobertura + schema do gabarito**: grupo só conta com cobertura ≥ ~30 % dos frames ativos; `validate_schema()` falhando alto (pose ausente, fps≤0, ids); consumir `visibility/presence` já capturados | Nota deixa de ser descontínua na detecção; gabarito malformado falha em vez de mentir | ~65 linhas | Baixo | P–M |
| 15 | **Segmentação**: trocar segmentos indexados por trimming de repouso nas pontas (+ DTW banded do item 7 faz o resto); consertar sobrescrita de fase (:913) e `_nan_to_zero` em sequências | Elimina o pareamento errado do movimento pós-toque; fase passa a existir de fato | Baixa | Baixo | P–M |
| 16 | **Calibração por sinal** (item P4 do plano de testes): dataset K×M×N, DBA opcional para template multi-take, thresholds por percentil, EER/matriz de confusão na tese | Transforma os limiares arbitrários em resultado científico — **o capítulo de avaliação da tese** | Média (maioria coleta) | Baixo | G |
| 17 | **Extrair `CaptureService`**: nó não-UI tipado com API pública (`start_capture(duração)`, `reset()`, sinais tipados), demo do GDMP para pasta `demo/`, sinal `landmarks_detected(export_data: Dictionary)` tipado, fim do duck-typing | Remove a classe inteira de falhas silenciosas; pré-requisito de teste de integração | Média (mecânica) | Baixo | M |
| 18 | **UX do feedback**: "Ver módulos" → `go_to_map()`, botão real de retry, tentativas incrementadas, título condicionado às estrelas, estado de erro real p/ `ok=false`; **checklist/ring**: ligar em `frame_instant_similarity` throttled (5 Hz) **ou deletar** | Visível em toda sessão; UI que simula capacidade inexistente é flag de banca | Baixa | Baixo | P–M |
| 19 | **Espelhamento dos previews**: flip só no caminho cru (ou ambos via viewport), rotação no preview cru | Overlay não deve inverter o mundo ao ligar | Baixa | Baixo | P |
| 20 | **Higiene**: deletar legado inalcançável (`Screen Scripts`, MainMenu/LearningMap/PlayerStats, scratch da raiz), `Themecreator` → EditorScript, `anim_cache` com dump opt-in + `clear_cache()` no boot, extrair componente único do mapa (des-duplicar Main/LessonMapScreen), caminho do rig via método no avatar, README + spec do formato JSON | Base limpa para publicação; bug fixes param de precisar ser feitos 2× | Baixa | Baixo | M |
| 21 | **CI**: lint enforced, release só em tags, remover .NET, job de teste (item 11) | CI que mente é pior que sem CI | Baixa | Nenhum | P |

## BAIXO — polimento e dívida

| # | Item | Por quê | Esf. |
|---|---|---|---|
| 22 | fps `(n−1)/duração` no export (off-by-one `HolisticLandmarker.gd:474-478`); unificar com `_estimate_fps` | Pipeline de medição da tese consistente | P |
| 23 | Não semear progresso falso `{1: completed, 3★}` (`Global.gd:188`); salvar com tmp+rename | Corrompe dados de avaliação coletados com o app | P |
| 24 | Resolver renderer (`mobile` vs. tag GL Compatibility); passada de métricas phone-first na UI; nav morta do Main | Decisão não tomada escondida na config | M |
| 25 | **Dieta do repositório**: GDMP só arm64 (resto via release/LFS), `.gitignore` p/ `.blend1`/`.tmp`, `git filter-repo` para o tscn de 88 MB, blends históricos, **modelo ripado** e a chave de API | 665 MB → ~80 MB; remove risco de licenciamento | M (coordenar rewrite) |
| 26 | Colapsar `LessonStateMachine` em enum+método no LessonScreen; menores de performance (P8) | Deleção líquida de código | P |

## Sequência recomendada

**Sprint 1 (destravar o produto):** 1 → 2 → 3 → 4 → 12 → 18 (parcial) — quase tudo trivial, e ao fim o app *funciona de verdade* no Android, com nota que conta e sem o falso positivo do usuário imóvel.
**Sprint 2 (blindar antes de mexer no núcleo):** 11 (testes pinando comportamento) → 8 (descongelar) → 9 (ciclo de vida/threads) → 5 (segurança).
**Sprint 3 (o método da tese):** 6 (espelhamento, com verificação empírica) → 7 (DTW real) → 10 (normalização espacial) → 13/14/15.
**Sprint 4 (a ciência):** 16 (dataset + calibração + EER) + 17/20/21 + escrita.

---

---

# Fase 5 — Execução (registro de implementação)

## Sprint 1 — destravar o produto

Itens 1–4, 12 e 18 (parcial). Permissão de câmera no Android (preset + runtime); catálogo normalizado para `{id, nome}` e `debug_lesson_id = -1` (a seleção de lição passou a funcionar); estrelas reais persistidas (melhor por sinal, mínimo na lição, sem rebaixar resultado anterior); **dados ausentes penalizados** (grupo exigido pelo gabarito e não executado vale 0%, com flag `_missing_groups`; usuário sem movimento recebe fase 0); suporte a canhotos por comparação espelhada; botões e textos do feedback corrigidos.

## Sprint 2 — blindar antes de mexer no núcleo

Suíte GUT com pins de regressão **criada antes** de qualquer mudança no algoritmo, para que toda alteração numérica ficasse visível no diff. Depois: remoção do DTW morto e indexação O(1) dos landmarks (−62% no custo por validação, sem mudar um único número — provado pelos pins); validação movida para `WorkerThreadPool` (fim do congelamento de 2–8 s); ciclo de vida da câmera (pausa fora da gravação, cancelamento não mata mais o feed, race de thread eliminada); chave de API fora do código e validador anti-RCE do `.tres` remoto.

## Sprint 3 — o método da tese

Ordem de implementação seguindo o fluxo dos dados: filtragem → normalização → alinhamento → agregação.

| Item | O que mudou | Resultado medido |
|---|---|---|
| 13 — filtragem | Filtro **One-Euro de fase zero** (duas passadas) nos dois lados | Ruído −56% (gabarito) e −83% (celular); trajetória 33%/10% **mais fiel** que o sinal cru. Atraso de fase eliminado: centroide temporal cru 15,000 → causal 15,810 → duas passadas 15,028 |
| 10 — normalização | Base afim do **tronco** (origem no meio dos quadris, eixos ombros/tronco) | Cancela algebricamente o formato da imagem. O mesmo osso a 45° media −60,6° em paisagem e −29,4° em retrato: **31,3° de erro puro** eliminados. Em dados reais, similaridade de pose 60,23% → 65,38% |
| 7 — alinhamento | **DTW multivariado** com banda de Sakoe-Chiba (15%) e backtracking do caminho ótimo, sobre todos os ossos do grupo | Em gabarito real: execução 0,5 s atrasada **83,14% → 99,98%** (+16,84); captura em taxa menor **69,38% → 93,89%** (+24,51); usuário parado permanece em 21,77% |
| 15 — movimento | Percurso total no lugar do emparelhamento de segmentos por índice | Independente da taxa: 15 fps vs 30 fps → 94,9%; metade do percurso → 48,3% |
| 14 — cobertura | Fator **contínuo** de cobertura de detecção + validação de formato do gabarito | Cobertura 0,20 contra gabarito 1,00 → fator 0,667. Gabarito sem pose passa a falhar alto em vez de silenciar a avaliação da localização do sinal |

**Efeito prático sobre as estrelas.** Com os limiares atuais (0,9/0,7/0,5), uma execução correta porém atrasada saía com 2 estrelas e agora sai com 3; uma gravada em fps menor saía com 1 estrela e agora sai com 3. O falso positivo do usuário imóvel continua barrado (21,8% = 0 estrela).

**Custo.** Pipeline completo, no desktop: 142 ms para 2,5 s de captura, 380 ms para 5 s, 717 ms para 10 s (o DTW domina e cresce quadraticamente). Roda em worker thread desde o Sprint 2, então não bloqueia a interface.

**Reprodutibilidade.** `enable_smoothing`, `enable_body_normalization` e `enable_dtw_alignment` permitem reproduzir cada ablação da tabela. `tools/medir_real.gd` e `tools/medir_custo.gd` reproduzem as medições sobre dados reais; `tests/fixtures/ref_abacaxi.json` é um gabarito real da API commitado como fixture. A suíte tem 112 testes.

**Limpeza.** Removidas as funções superadas pelo novo alinhamento (`series_to_angle_diff`, `compute_dtw_distance`, `segment_similarity_dtw`, `normalize_sequence`, `weighted_mean_angle` e dependências): manter duas implementações de DTW lado a lado reproduziria a ambiguidade que tornava o código original enganoso. Os pins não se moveram, confirmando que o código removido era inalcançável.

## O que continua pendente

1. **Verificação empírica do contrato de espelhamento (item 6).** A canonicalização está implementada e é algebricamente correta, mas a confirmação exige uma captura do usuário **executando o sinal do gabarito**. O teste com uma captura qualquer (pessoa parada) mede só assimetria de postura e não decide nada — `tools/medir_real.gd` roda o experimento assim que essa gravação existir.
2. **Item 16 — calibração por sinal (dataset K×M×N, limiares por percentil, EER).** É o capítulo de avaliação da tese e depende de coleta.
3. **Item 18 — feedback em tempo real.** `frame_instant_similarity` continua sem chamadores: ou é ligado ao anel de precisão/checklist, ou os dois são removidos. É decisão de produto.
4. **`visibility`/`presence`** seguem capturados e não consumidos.
5. Rotacionar a chave da API (a antiga está no histórico do git) e criar o secret `PENO_API_KEY` no GitHub.
