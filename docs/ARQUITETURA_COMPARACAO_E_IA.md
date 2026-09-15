# Arquitetura Técnica Completa do Sistema de Comparação e Reconhecimento de LIBRAS

**Data de Consolidação:** Setembro de 2026  
**Escopo:** Pipeline de ponta a ponta — da extração de sementes cinemáticas e síntese de dados ao treinamento da rede neural profunda e ao validador híbrido em tempo real no Godot Engine.  
**Repositórios Envolvidos:** `TCC` (Pesquisa, Calibração, Síntese e Treinamento) e `PENO` (Aplicação Interativa, Validação Paralela e Visualização).

---

## Sumário Executivo

O sistema de avaliação de Libras (*Língua Brasileira de Sinais*) desenvolvido neste projeto implementa um **modelo híbrido paralelo** capaz de avaliar simultaneamente dois pilares fonológicos fundamentais da linguagem gestual:

1. **Pilar Espacial e Cinemático (Movimento, Posição e Orientação do Corpo):** Avalia a localização do sinal no tronco e o movimento executado no espaço por meio de *Dynamic Time Warping* (DTW) multivariado com banda de Sakoe-Chiba, normalização anatômica pelo tronco (*BodyFrame*) e suavização de fase zero (*One-Euro Filter*).
2. **Pilar Biomecânico da Forma da Mão (Configuração Fina dos Dedos):** Avalia a postura e articulação dedo a dedo por meio de uma Rede Neural Profunda (*Deep Feedforward Multi-Layer Perceptron*) treinada sobre um espaço taxonômico discreto de **2.364 classes anatômicas reais** (*DADADADAFP*), estabilizada temporalmente por Média Móvel Exponencial (EMA) e filtro de mediana.

O validador oficial pondera **70% para a Forma da Mão** (rede neural de IA) e **30% para o Movimento e Posição Corporal** (cinemática/DTW), com tolerâncias biomecânicas rigorosas e penalidades estritas para mãos ausentes ou configurações divergentes.

```
                                  FLUXO GERAL DE PONTA A PONTA
                                  
 [Calibração Guiada] ──► [Fusão Duplo Plano] ──► [Referencial Canônico] ──► [Poda Anatômica]
   (Câmera Web 2D)        (Coronal XY + Sagital YZ)   (Palma Ortonormal)       (Juncturae Tendinum)
                                                                                     │
                                                                                     ▼
 [Deploy GDScript] ◄── [Conversão TFLite] ◄── [Treinamento DNN] ◄── [Gerador Sintético 3D]
  (weights.bin / .json)    (modelo_gestos.tflite)    (MLP 42->512->2364)    (2,3M amostras em domo)
         │
         ▼
 ┌────────────────────────────────────────────────────────────────────────────────────────┐
 │                              APLICAÇÃO INTERATIVA (PENO)                               │
 │                                                                                        │
 │   Câmera (30 FPS) ──► MediaPipe Holistic ──► SubViewport (Readback Otimizado)           │
 │                                                         │                              │
 │                                                         ▼                              │
 │                                            ParallelSignValidator                       │
 │                                        ┌─────────────────────────┐                     │
 │                                        │                         │                     │
 │                       [Pilar Cinemático/DTW]          [Pilar Neural de Forma]          │
 │                       • OneEuroFilter (2 passos)      • 42 Features Relativas          │
 │                       • BodyFrame (Tronco 3D)         • HandNeuralEngine (Zero-Alloc)  │
 │                       • DTW Multivariado Banda        • Suporte Bimanual (Espelho L)   │
 │                       • Orientação da Palma / Dir.    • EMA (150ms) + Mediana Dedos    │
 │                       • Peso: 30%                     • Peso: 70%                      │
 │                                        │                         │                     │
 │                                        └────────────┬────────────┘                     │
 │                                                     │                                  │
 │                                                     ▼                                  │
 │                                  Nota Final Ponderada & Tolerâncias                    │
 │                                                     │                                  │
 │                                                     ▼                                  │
 │                                  ComparisonCard & FeedbackState                        │
 └────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 1. Contexto e Motivação: Por que um Novo Pilar de Forma da Mão?

### 1.1 Limitações da Visão Monocular 2D e do DTW Isolado
Historicamente, o comparador cinemático (`Comparador.gd`) avaliava a execução comparando vetores unitários de ossos normalizados entre o usuário e o gabarito. Contudo, essa abordagem sofria de três fragilidades críticas para a avaliação pedagógica de Libras:
1. **Ruído de Profundidade (Eixo Z):** Em câmeras monoculares, estimativas de profundidade do MediaPipe sofrem instabilidade severa. Uma rotação leve do pulso (~68° em *yaw*) distorcia o produto vetorial da palma, fazendo com que dedos flexionados parecessem apontar lateralmente.
2. **Ambiguidade Anatômica:** O DTW calcula distâncias angulares globais. Um usuário que fechava o indicador mas mantinha o médio aberto podia obter pontuação similar à de quem posicionava os dedos corretamente, porque a média vetorial atenuava erros locais.
3. **Falta de Semântica Biomecânica:** A cinemática pura não sabia explicar *qual* dedo estava errado e *como* o aluno deveria corrigi-lo.

### 1.2 A Abordagem do Classificador Biomecânico (TCC)
Para resolver esse problema, introduziu-se a taxonomia cinesiológica **DADADADAFP**. Em vez de tratar a mão como uma nuvem contínua de pontos sujeita a ruídos de escala e rotação, a postura da mão é classificada em um conjunto discreto e bem definido de configurações de falanges (estágios de flexão e abdução).

Ao desacoplar a **configuração articular da mão** (resolvida pela rede neural) da **trajetória espacial do movimento** (resolvida pelo DTW e BodyFrame), a aplicação passa a validar sinais estáticos e dinâmicos com precisão milimétrica e diagnósticos compreensíveis.

---

## 2. Obtenção de Dados e Criação das Sementes Cinemáticas (*Seeds*)

A construção do modelo neural não utiliza fotos aleatórias da internet, mas uma base semente estritamente calibrada e matematicamente reconstruída em 3D.

```
             FUSÃO MULTIPLANAR E CINEMÁTICA DIRETA CANÔNICA
             
   Ângulo Frontal (XY)            Ângulo Lateral 90° (YZ)
     [Câmera Web 2D]                [Câmera Web 2D]
            │                               │
            └───────────────┬───────────────┘
                            ▼
              fuse_dual_plane_landmarks()
        (X, Y da frontal + Z do perfil lateral)
                            │
                            ▼
               Preservação Rígida de Óssos
                 (L1, L2, L3 constantes)
                            │
                            ▼
               Sistema Canônico da Palma
             (Metacarpos alinhados com ΔZ = 0)
                            │
                            ▼
               Poda Juncturae Tendinum
              (Elimina 204 classes inviáveis)
                            │
                            ▼
              2.364 Sementes 3D Oficiais
```

### 2.1 Calibração Guiada por Visão Dupla (*Dual Plane Fusion*)
A obtenção dos dados-base ocorre através dos scripts `guided_hand_calibrator.py` e `guided_thumb_calibrator.py`:
- **Protocolo de Dois Ângulos:** Para cada postura anatômica necessária, o usuário posiciona a mão na frente da webcam e mantém estabilidade por 1.2 segundos em dois ângulos sequenciais:
  1. **Plano Frontal (Coronal XY):** Extrai a projeção lateral e vertical com máxima definição de abertura de dedos (*spread*).
  2. **Plano de Perfil 90° (Sagital YZ):** Extrai a profundidade real de flexão das falanges.
- **Fusão Planar:** A função `fuse_dual_plane_landmarks()` unifica as coordenadas:
  $$P_{\text{fused}} = \begin{bmatrix} X_{\text{frontal}} \\ Y_{\text{frontal}} \\ Z_{\text{perfil}} \end{bmatrix}$$
- **Preservação de Comprimento Ósseo:** Os comprimentos das falanges ($L_1, L_2, L_3$) obtidos na postura aberta basal são mantidos rigorosamente constantes via cinemática direta, impedindo que a mão encolha artificialmente durante flexões acentuadas.

### 2.2 Formulação Matemática do Referencial Canônico da Palma
Para eliminar qualquer dependência de como a mão do usuário está orientada em relação à câmera no momento da calibração, o script `kinematic_seed_generator.py` projeta todos os 21 pontos no **Sistema Ortonormal Canônico da Palma**:

1. **Origem:** Landmark 0 (Pulso), $\vec{P}_0 = (0, 0, 0)$.
2. **Eixo Longitudinal $\hat{e}_y$:** Alinhado do pulso ao metacarpo médio (Landmark 9), invertido para coordenadas de tela:
   $$\vec{v}_y = \frac{\vec{P}_9 - \vec{P}_0}{\|\vec{P}_9 - \vec{P}_0\|}, \quad \hat{e}_y = -\vec{v}_y$$
3. **Eixo Transversal $\hat{e}_x$:** Alinhado do metacarpo do indicador (5) ao mindinho (17), ortogonalizado em relação a $\hat{e}_y$ via processo de Gram-Schmidt:
   $$\vec{v}_x^{\text{raw}} = \vec{P}_{17} - \vec{P}_5$$
   $$\vec{v}_x = \vec{v}_x^{\text{raw}} - (\vec{v}_x^{\text{raw}} \cdot \hat{e}_y) \hat{e}_y, \quad \hat{e}_x = \frac{\vec{v}_x}{\|\vec{v}_x\|}$$
4. **Eixo Normal da Palma $\hat{e}_z$:** Perpendicular à palma da mão, apontando diretamente para o observador (+Z):
   $$\hat{e}_z = \frac{\hat{e}_x \times \hat{e}_y}{\|\hat{e}_x \times \hat{e}_y\|}$$
5. **Matriz de Mudança de Base $R_{\text{canon}}$:**
   $$R_{\text{canon}} = \begin{bmatrix} \hat{e}_x^T \\ \hat{e}_y^T \\ \hat{e}_z^T \end{bmatrix}, \quad \vec{P}_{\text{canon}} = R_{\text{canon}} (\vec{P} - \vec{P}_0)$$

**Garantias Biomecânicas da Transformação:**
- Os nós metacarpais do indicador (5) e do mindinho (17) ficam estritamente no mesmo plano $Z$ ($\Delta Z = 0.000000$).
- A flexão sagital dos 4 dedos longos ocorre estritamente no plano $YZ$ ($\Delta X = 0$).

### 2.3 Taxonomia DADADADAFP
A anatomia de cada semente é serializada em uma cadeia de 10 dígitos:
$$\text{Código} = [D_4][A_3][D_3][A_2][D_2][A_1][D_1][A_0][F][P]$$

| Dígito | Articulação | Valores | Descrição Biomecânica |
| :---: | :--- | :---: | :--- |
| **$D_4$** | Mindinho (Pinky) | `0`..`4` | `0`: Estendido, `1`: Curvado, `2`: Gancho, `3`: Plataforma, `4`: Fechado |
| **$A_3$** | Abertura Mindinho-Anelar | `0`, `1` | `0`: Aberto em leque, `1`: Fechado paralelo |
| **$D_3$** | Anelar (Ring) | `0`..`4` | `0`: Estendido, `1`: Curvado, `2`: Gancho, `3`: Plataforma, `4`: Fechado |
| **$A_2$** | Abertura Anelar-Médio | `0`, `1` | `0`: Aberto em leque, `1`: Fechado paralelo |
| **$D_2$** | Médio (Middle) | `0`..`4` | `0`: Estendido, `1`: Curvado, `2`: Gancho, `3`: Plataforma, `4`: Fechado |
| **$A_1$** | Abertura Médio-Indicador | `0`, `1` | `0`: Aberto em 'V', `1`: Fechado em 'U' |
| **$D_1$** | Indicador (Index) | `0`..`4` | `0`: Estendido, `1`: Curvado, `2`: Gancho, `3`: Plataforma, `4`: Fechado |
| **$A_0$** | Abertura Indicador-Polegar | `0`, `1` | `0`: Abdução radial total (aberto em 90°), `1`: Aduzido colado |
| **$F$** | Oposição Transversal | `0`, `1` | `0`: No plano da palma, `1`: Cruzando a frente da palma |
| **$P$** | Ponta do Polegar (IP) | `0` | Fixado em 0 na simplificação canônica |

### 2.4 Poda Biomecânica Anatômica (*Juncturae Tendinum*)
A multiplicação combinatória das juntas geraria 3.936 classes. No entanto, a mão humana possui limitações anatômicas intrínsecas:
- **Faixas Tendíneas Interdigitais (*Juncturae Tendinum*):** Os tendões extensores dos dedos Anelar e Mínimo compartilham conexões fibrosas na fáscia dorsal da mão. Fisiologicamente, é impossível manter o dedo Anelar totalmente esticado ($D_3 = 0$) enquanto o Mínimo está completamente dobrado contra a palma ($D_4 \ge 3$).
- O script `prune_impossible_classes.py` aplicou essa poda cinesiológica, eliminando **204 classes inviáveis** e consolidando o catálogo oficial em exatamente **2.364 classes anatômicas reais** registradas em `seeds.json`.
- O sinal da letra 'W' foi padronizado canonicamente como `1000000110` (Indicador, Médio e Anelar erguidos; Mínimo curvado natural em estágio 1).

---

## 3. Geração da Base Sintética e Aumentação de Dados (`synthetic_generator.py`)

Com as 2.364 poses semente consolidadas, foi necessário criar um simulador capaz de gerar variações de ponto de vista, distância, perspectiva e imperfeições de hardware.

```
                   PIPELINE DE SÍNTESE ESPACIAL 3D
                   
       Semente 3D Canônica (21 Landmarks x 2.364 Classes)
                               │
                               ▼
        Varredura Esférica 3D Contínua (Spherical Bouncing)
          • Roll: 0 a 720° (2 voltas completas)
          • Pitch: -65° a +65°
          • Yaw: -65° a +65°
                               │
                               ▼
            Projeção em Perspectiva com Fator Z
               Z_factor = offset / (offset - Z)
                               │
                               ▼
           Bounding Box Unitária e Normalização [0, 1]
                               │
                               ▼
           Injeção de Ruído Gaussiano N(0, 0.005)
                               │
                               ▼
         Dataset Final: 600 amostras/classe = ~1,42M frames
```

1. **Aumentação Esférica Contínua (*Spherical Bouncing*):**
   Para cada semente, são geradas 600 instâncias sob ângulos tridimensionais suaves calculados via funções de onda (`bounce_wave`):
   - **Roll:** $0^\circ$ a $720^\circ$ (simulando giros completos da mão ou da câmera).
   - **Pitch:** $-65^\circ$ a $+65^\circ$ (inclinação vertical da mão).
   - **Yaw:** $-65^\circ$ a $+65^\circ$ (inclinação lateral).
   Multiplicações sucessivas pelas matrizes de rotação Eulerianas $R_x(\theta), R_y(\phi), R_z(\psi)$ transformam as coordenadas canônicas.
2. **Projeção em Perspectiva Cônica (Fator Z):**
   Câmeras reais não são ortográficas. Para simular a dilatação geométrica quando dedos apontam para a lente, aplica-se a transformação de perspectiva:
   $$X' = X \cdot \left(\frac{Z_{\text{offset}}}{Z_{\text{offset}} - Z}\right), \quad Y' = Y \cdot \left(\frac{Z_{\text{offset}}}{Z_{\text{offset}} - Z}\right)$$
3. **Normalização em Bounding Box Relativa:**
   A malha 2D projetada é enquadrada em sua caixa delimitadora mínima e escalonada para o intervalo $[0.0, 1.0]$.
4. **Ruído Gaussiano de Sensor:**
   Adiciona-se perturbação gaussiana $\epsilon \sim \mathcal{N}(0, 0.005)$ nas coordenadas normalizadas de cada nó, mimetizando tremores de captura do MediaPipe, baixa luminosidade e distorções de lente.

Volume resultante: **2.364 classes $\times$ 600 amostras = 1.418.400 amostras sintéticas**.

---

## 4. Treinamento da Rede Neural e Exportação (`neural_engine.py`)

### 4.1 Vetor de Entrada (42 Features Relativas)
A entrada da rede neural é composta por 42 valores em ponto flutuante ($21 \text{ landmarks} \times 2 \text{ eixos}$):
1. Calcula-se a *bounding box* da mão: $[x_{\min}, x_{\max}]$ e $[y_{\min}, y_{\max}]$.
2. Fator de escala: $\text{size} = \max(x_{\max} - x_{\min}, y_{\max} - y_{\min}, 10^{-6})$.
3. Pulso normalizado: $w_x = (x_0 - x_{\min}) / \text{size}$, $w_y = (y_0 - y_{\min}) / \text{size}$.
4. Para cada landmark $i \in [0, 20]$:
   $$\text{feature}_{2i} = \frac{x_i - x_{\min}}{\text{size}} - w_x, \quad \text{feature}_{2i+1} = \frac{y_i - y_{\min}}{\text{size}} - w_y$$
Isso garante invariância rigorosa a translações e escalas absolutas da mão no quadro da câmera.

### 4.2 Pipeline de Dados e Espelhamento em Memória
- **Cache Incremental Compacto:** Os dados sintéticos são convertidos e armazenados em arquivos binários compactados `.npz`.
- **Espelhamento Algorítmico em RAM:** Ao carregar a base na RAM, a matriz de treinamento dobra de tamanho instantaneamente invertendo o eixo X:
  $$X_{\text{data}}[\text{mirror\_offset}:, 0::2] \times= -1$$
  Isso ensina a rede a reconhecer mãos esquerdas e destras sem precisar sintetizar ou ler novos arquivos em disco.

### 4.3 Topologia da Rede Neural (MLP Profundo)
A arquitetura foi desenhada para altíssima acurácia com pegada de memória mínima e latência sub-milissegundo:

```
 Entrada (42 Features)
    │
    ▼
 Camada Densa 1 (512 Neurônios) ──► BatchNormalization ──► ReLU ──► Dropout(0.2)
    │
    ▼
 Camada Densa 2 (256 Neurônios) ──► BatchNormalization ──► ReLU ──► Dropout(0.2)
    │
    ▼
 Camada Densa 3 (128 Neurônios) ──► BatchNormalization ──► ReLU
    │
    ▼
 Camada Densa 4 (2.364 Neurônios) ──► Softmax (Probabilidade por Classe)
```

- **Otimizador:** Adam ($\text{lr} = 0.001$).
- **Função de Perda:** *Categorical Crossentropy*.
- **Regularização:** *BatchNormalization* em todas as camadas ocultas para mitigar *covariate shift* interno, com *Dropout* de 20% nas camadas maiores.
- **Convergência:** Parada antecipada (*EarlyStopping*) com paciência de 15 épocas restaurando os melhores pesos.

### 4.4 Métricas Obtidas
- **Acurácia de Validação:** **99.84%**
- **Loss de Validação:** **0.0050**
- **Época de Convergência Ótima:** Época 64 de 150.

### 4.5 Exportação e Deploy Multiplataforma
1. **Modelo TFLite (`modelo_gestos.tflite`):** Modelo compilado com quantização de grafos (1.96 MB, tempo de inferência ~0.6 ms).
2. **Binário de Pesos Contíguos (`weights.bin`):** Para o Godot Engine, os pesos e bias de ponto flutuante de 32 bits de todas as camadas e os parâmetros de escala/offset da Batch Normalization foram serializados sequencialmente em um arquivo binário bruto de 1.971.972 bytes.
3. **Mapeamento de Labels (`labels.json`):** Catálogo contendo a ordem exata das 2.364 strings de 10 dígitos.

---

## 5. Motor de Inferência Nativo em GDScript (`HandNeuralEngine.gd`)

Para permitir que o modelo execute no Godot sem a necessidade de compilar bibliotecas C++ externas complexas ou depender do runtime do TensorFlow Lite em todas as plataformas, foi implementado um motor de inferência matricial nativo em GDScript puro (`HandNeuralEngine.gd`).

### 5.1 Otimizações de Baixo Nível (Zero-Alloc Heap)
Em dispositivos móveis ou notebooks com poucos recursos, alocações contínuas de memória no heap causam interrupções frequentes pelo *Garbage Collector*. O `HandNeuralEngine` implementa as seguintes técnicas de alta performance:

1. **Buffers Pré-Alocados:** Todos os vetores intermediários de ativação são alocados uma única vez na inicialização:
   - `_z0` e `_a0`: 512 floats
   - `_z1` e `_a1`: 256 floats
   - `_z2` e `_a2`: 128 floats
   - `_z3` e `_probs`: 2.364 floats
2. **Bypass Esparso após ReLU:**
   Na multiplicação matricial $Z = W \cdot A + B$, caso uma ativação da camada anterior seja zero ($A_i == 0.0$, o que ocorre frequentemente após a ReLU), o loop interno daquela linha é pulado imediatamente:
   ```gdscript
   for i in range(M):
       var xi := x[i]
       if xi == 0.0:
           continue # Pula N multiplicacoes e somas no produto interno
       var row_offset := i * N
       for j in range(N):
           out[j] += xi * W[row_offset + j]
   ```
3. **Fusão de ReLU e Batch Normalization:**
   A aplicação da não-linearidade e o escalonamento da normalização são processados no mesmo loop linear:
   $$\text{out}_j = \begin{cases} z_j \cdot \text{scale}_j + \text{offset}_j, & \text{se } z_j > 0 \\ \text{offset}_j, & \text{caso contrário} \end{cases}$$
4. **Softmax Estável:**
   Para prevenir *overflow* de ponto flutuante, subtrai-se o valor máximo antes do cálculo exponencial:
   $$P_j = \frac{e^{z_j - \max(Z)}}{\sum_{k} e^{z_k - \max(Z)}}$$

### 5.2 Validação de Paridade com o Modelo Python
O arquivo `sanity_test.json` armazena uma entrada de teste gerada no Python com o vetor de saída esperado. O método `run_sanity_test()` valida em runtime se a confiança calculada no Godot confere com a do Keras com diferença inferior a $10^{-4}$ ($\Delta < 0.0001$). O teste é executado e passa com 100% de precisão.

---

## 6. Classificador Temporal e Suporte Bimanual (`HandShapeClassifier.gd`)

A saída de um modelo neural em quadros isolados sofre pequenas variações a cada frame decorrentes de ruído de iluminação e micro-oclusões. O `HandShapeClassifier.gd` atua como uma camada de estabilização temporal e semântica.

```
                  ESTABILIZAÇÃO TEMPORAL E BIMANUAL
                  
               Landmarks da Câmera (Mão Direita ou Esquerda)
                                      │
                   ┌──────────────────┴──────────────────┐
                   ▼                                     ▼
             [Mão Direita]                         [Mão Esquerda]
             (Coordenadas Naturais)                (Espelhamento: X = 1.0 - X)
                   │                                     │
                   ▼                                     ▼
        Vetor de Probabilidades               Vetor de Probabilidades
        Instatâneo (2.364 classes)            Instatâneo (2.364 classes)
                   │                                     │
                   ▼                                     ▼
        Média Móvel Exponencial (EMA)         Média Móvel Exponencial (EMA)
             (tau = 150 ms)                        (tau = 150 ms)
                   │                                     │
                   ▼                                     ▼
        Filtro de Mediana nos Dedos           Filtro de Mediana nos Dedos
             (Janela de 5 frames)                  (Janela de 5 frames)
                   │                                     │
                   └──────────────────┬──────────────────┘
                                      ▼
                        Código Estabilizado e Guidance
                         (Thumb, Index, Middle, etc.)
```

### 6.1 Suporte Bimanual com Espelhamento Canônico
A rede neural foi treinada primariamente no referencial de mão direita. Para avaliar a mão esquerda (seja de um usuário canhoto ou em sinais que utilizam ambas as mãos):
- Os landmarks são espelhados horizontalmente antes da extração de features:
  $$X_{\text{canônico}} = 1.0 - X_{\text{camera}}$$
- Isso projeta a mão esquerda no mesmo espaço de coordenadas canônico que o modelo reconhece com maestria, eliminando a necessidade de treinar redes distintas.

### 6.2 Estabilização Temporal em Dois Níveis
1. **Média Móvel Exponencial (EMA) nas Probabilidades:**
   O vetor de probabilidades brutas $P$ é suavizado a cada instante com base no tempo decorrido $\Delta t$:
   $$\alpha = 1 - e^{-\frac{\Delta t}{\tau}}, \quad \text{onde } \tau = 150\text{ ms}$$
   $$P_{\text{smooth}}^{(t)} = \alpha P_{\text{raw}}^{(t)} + (1 - \alpha) P_{\text{smooth}}^{(t-1)}$$
   Isso atenua oscilações bruscas de classificação mantendo alta responsividade a mudanças reais de postura.
2. **Filtro de Mediana nos Estágios dos Dedos:**
   Uma janela deslizante de 5 amostras armazena o histórico recente. Para cada um dos quatro dedos longos ($D_4, D_3, D_2, D_1$), o dígito final é a mediana da janela. Se a mão piscar por 1 frame devido a oclusão rápida, o filtro elimina o *spike* espúrio.

### 6.3 Otimização para Dispositivos Móveis (*Adaptive Stride*)
Em gravações de vídeos mais longos (acima de 30 ou 60 frames), analisar todos os quadros consecutivamente sobrecarregaria a CPU de celulares.
- Se a gravação tem mais de 30 frames: passo de amostragem $\text{stride} = 2$.
- Se a gravação tem mais de 60 frames: passo de amostragem $\text{stride} = 3$.
Essa técnica mantém a taxa de análise em ~15 a 20 FPS, cortando em até 66% as inferências com perda nula de precisão.

### 6.4 Cálculo de Precisão com Foco no Ápice (*Top 70% Apex Average*)
Em exercícios práticos de Libras, o usuário inicia com a mão em repouso, ergue a mão, executa o sinal e depois a abaixa. Avaliar todos os quadros igualmente penalizaria os momentos de transição:
- Quadros sem detecção de mãos são ignorados na média de similaridade.
- A lista de similaridades dos quadros detectados é ordenada, e calcula-se a média dos **70% quadros com maior pontuação** (o ápice da execução).
- A precisão final da mão combina a postura sustentada dominante com o ápice:
  $$\text{Precisão}_{\text{mão}} = 0.70 \times \text{Similaridade}_{\text{dominante}} + 0.30 \times \text{Similaridade}_{\text{ápice}}$$

---

## 7. O Pilar Cinemático e Espacial (`Comparador.gd` e `MotionWrapper.gd`)

Enquanto a rede neural analisa a configuração dos dedos, o comparador cinemático avalia a execução motora global no corpo do sinalizador.

### 7.1 Suavização One-Euro de Fase Zero
O ruído de alta frequência do MediaPipe é filtrado através do `OneEuroFilter.gd`, que aplica uma passagem progressiva e uma regressiva (*zero-phase filtering*) nos quadros do usuário e da referência. Isso estabiliza os vetores 3D sem introduzir atraso de fase no início do movimento.

### 7.2 Normalização de Tronco (`BodyFrame.gd`)
Para desvincular a análise da distância da pessoa até a câmera ou da proporção da tela (celular em pé vs gravação em paisagem):
- Constrói-se uma base ortonormal 3D com origem no centro dos quadris (Landmarks 23 e 24) e orientação determinada pelos ombros (11 e 12).
- Todas as coordenadas corporais e manuais são expressas nesse referencial normalizado de tronco.

### 7.3 DTW Multivariado com Banda de Sakoe-Chiba
O alinhamento temporal entre a execução do aluno (que pode estar em 15 ou 24 FPS) e a referência (30 FPS) é realizado por *Dynamic Time Warping*:
- **Banda de Sakoe-Chiba (15%):** Restringe a busca em torno da diagonal temporal, impedindo distorções patológicas (um frame inicial casando com metade do vídeo).
- **Custo Local por Distância de Corda:** Para evitar milhares de chamadas trigonométricas de arco-cosseno no preenchimento da matriz, calcula-se a distância de corda ponderada:
  $$\text{Custo}(i, j) = \frac{\sum_{\text{ossos}} w_b \cdot (1 - \vec{v}_a \cdot \vec{v}_b)}{\sum w_b}$$
- O caminho ótimo de alinhamento é recuperado por *backtracking*, e os ângulos exatos em graus são computados somente ao longo do caminho traçado.

### 7.4 Quantidade de Movimento e Orientação da Palma
- **Percurso Vetorial (Travel):** Compara a integral do deslocamento vetorial (comprimento total da trajetória percorrida pela mão). Se a referência exige movimento e o aluno fica estático, recebe nota de fase zero.
- **Normal da Palma e Vetor Diretor:** Mede o produto vetorial da palma e a direção do pulso à ponta do dedo médio, ponderando desvios na rotação do punho.

---

## 8. Validação Paralela Híbrida e Ponderação Oficial (`ParallelSignValidator.gd`)

O `ParallelSignValidator.gd` é a classe central que orquestra a execução conjunta de ambos os pilares e produz o veredito oficial do sistema.

```
                 ORQUESTRAÇÃO DO PARALLEL SIGN VALIDATOR
                 
                          Gravação do Usuário
                                   │
                                   ▼
                 Trava de Proteção de Frames (> 250 frames)
                   (Subamostra para 200 frames de segurança)
                                   │
                                   ▼
         ┌─────────────────────────┴─────────────────────────┐
         │                                                   │
         ▼                                                   ▼
 [Pilar Cinemático / DTW]                           [Pilar Neural IA]
 (MotionComparatorValidator)                        (HandShapeClassifier)
   • Pose corporal (ombros, braços)                   • Análise do sinal base (Cache)
   • DTW multivariado                                 • Extração bimanual (D + E)
   • Orientação da palma                              • Estabilização EMA + Mediana
   • Trajetória de movimento                          • 42 features relativas
         │                                                   │
         ▼                                                   ▼
  legacy_precision (30%)                              ai_precision (70%)
         │                                                   │
         └─────────────────────────┬─────────────────────────┘
                                   │
                                   ▼
                   Mãos detectadas na gravação?
                   ├── NÃO ──► Nota Final = 0.0, ok = false, "MISSING"
                   └── SIM ──► Combinação Ponderada:
                               Nota = (ai_precision * 0.70) + (legacy_precision * 0.30)
                                   │
                                   ▼
                   Envelope de Resultado Oficial & UI
```

### 8.1 Resolução de Sinais com Cache Estático Inteligente
Ao receber a referência da lição:
1. Identifica o código taxonômico esperado através do nome do sinal em `HandBiomechanicalGuidance.resolve_kinematic_code()`.
2. **Execução sobre o Sinal Base:** A rede neural também avalia os frames da gravação de referência da lição para extrair o código dominante exato do gabarito.
3. Para evitar que essa inferência no gabarito repita a cada tentativa do aluno na mesma lição, o resultado é mantido em um cache estático em memória (`_ref_eval_cache`).

### 8.2 Regra Fundamental de Ausência de Mãos
> **REGRA DE OURO:** Um sinal de Libras depende fundamentalmente do uso das mãos. Se a gravação do usuário contiver zero frames com mãos detectadas (`det_frames == 0`):
> - A pontuação final é obrigatoriamente **`0.0`**.
> - O sinal é marcado como reprovado (`overall_ok = false`).
> - A mensagem de erro orienta: *"Nenhuma mão detectada na gravação. Posicione sua mão visível em frente à câmera."*
> - Todos os dedos no diagnóstico articular recebem o estado `MISSING` com o rótulo visual `⚠️ Não detectado`.

### 8.3 Fórmula de Ponderação Oficial
Quando as mãos estão visíveis, a precisão global combina os dois pilares:
$$\text{Precisão Final} = (\text{Precisão da Forma da Mão} \times 0.70) + (\text{Precisão Cinemática de Movimento} \times 0.30)$$

- **Se a forma da mão estiver correta e o movimento compatível:** pontuação cheia ponderada.
- **Se a mão foi detectada mas a forma divergiu do sinal esperado:** pontua apenas a fração de posicionamento corporal ($\le 30\%$) e sinaliza reprovação (`overall_ok = false`).

---

## 9. Tolerâncias Rigorosas e Desconto Incisivo (`HandBiomechanicalGuidance.gd`)

A função `calculate_posture_similarity(detected_code, expected_code)` estabelece uma escala contínua com critérios estritos de aprovação:

```
        ESCALA DE PONTUAÇÃO POSTURAL DA FORMA DA MÃO
        
  1.00 ─── Perfeito (0 divergências)
  0.90 ─── 1 caractere com desvio de ±1 nível (ex.: curvado vs estendido suave)
  0.78 ─── 1 caractere com desvio de ±2 níveis
  0.75 ─── 2 caracteres com desvio de ±1 nível cada
  0.65 ─── 2 caracteres com desvio de ±1 e ±2 níveis
  0.55 ─── 2 caracteres com desvio de ±2 níveis cada
 ─────── LIMIAR DE REPROVAÇÃO RIGOROSA ──────────────────────────────────
  0.35 ─── Teto máximo para 3 caracteres divergentes
  0.18 ─── Teto máximo para 4 caracteres divergentes
  0.00 ─── Erro grosseiro (desvio >= 3 níveis, ex.: dedo aberto vs punho fechado)
```

### 9.1 Zona de Tolerância Aceitável
Permite pequenas variações anatômicas naturais (dedos ligeiramente mais curvados ou juntos):
- **0 caracteres divergentes:** Similaridade `1.0` (100%).
- **1 caractere com desvio de 1 nível:** `0.90` (90%).
- **1 caractere com desvio de 2 níveis:** `0.78` (78%).
- **2 caracteres com desvio de 1+1 níveis:** `0.75` (75%).
- **2 caracteres com desvio de 1+2 níveis:** `0.65` (65%).
- **2 caracteres com desvio de 2+2 níveis:** `0.55` (55%).

### 9.2 Zona de Desconto Incisivo
Se houver divergência em mais de 2 caracteres ou erro cinesiológico grave:
- **3 caracteres divergentes:** Teto máximo de `0.35` (reprovado automaticamente).
- **4 caracteres divergentes:** Teto máximo de `0.18`.
- **5 ou mais caracteres divergentes:** Nota residual próxima de `0.0`.
- **Desvio Anatômico Grosseiro ($\ge 3$ níveis):** Se qualquer dedo apresentar erro anatômico grave (ex.: dedo estendido reto quando deveria estar fechado contra a palma), aplica-se um multiplicador redutor de **0.35** sobre a nota residual, derrubando a pontuação para $\le 0.10$.

---

## 10. Otimizações de Desempenho e Proteções contra Travamentos

Durante os testes de estresse em hardware móvel e notebooks de entrada, foram diagnosticados e solucionados quatro gargalos críticos:

### 10.1 Limitador de Taxa de Inferência e Descarte por Contrapressão (*Backpressure Drop*)
- **Problema:** A câmera enviava quadros a até 114 FPS no monitor de alta taxa de atualização, enquanto o modelo em CPU processava a ~15 FPS. Isso gerava uma fila com atraso de até 58 segundos e vazamento de memória com 1,73 GB de RAM.
- **Solução em `HolisticLandmarker.gd`:**
  - Intervalo mínimo de inferência: `MIN_INFERENCE_INTERVAL_MS = 33` (~30 FPS).
  - Controle de contrapressão: `MAX_INFLIGHT_FRAMES = 1`. Se o MediaPipe ainda estiver processando o frame anterior, novos quadros da câmera são descartados imediatamente, mantendo a latência em zero.

### 10.2 Otimização do Readback GPU $\to$ CPU
- **Problema:** A chamada `texture.get_image()` realizava transferência síncrona pesada de textura da GPU para a CPU a cada frame (~300 MB/s de banda).
- **Solução:** Durante a exibição do avatar 3D (modo Showcase), a inferência é pausada (`_inference_paused = true`) e a transferência de texturas é pulada integralmente.

### 10.3 Trava de Segurança contra Gravações Gigantes e Travamento no DTW
- **Problema:** Se o temporizador de gravação atrasasse, uma captura prolongada podia gerar 15.000 frames (77 MB de JSON). O algoritmo DTW ($O(N \times M)$) tentava alocar matrizes com mais de 90 milhões de nós na thread principal, travando o computador a 100% de CPU.
- **Solução:**
  1. `HolisticLandmarker.gd`: Teto rígido `MAX_CAPTURE_FRAMES = 360` (~12 segundos a 30 FPS).
  2. `RecordingState.gd`: Emissão explícita do sinal `request_stop_capture` assim que o contador chega a 0.
  3. `ParallelSignValidator.gd`: *Downsampling* de proteção. Se a gravação contiver mais de 250 frames, reamostra proporcionalmente para 200 frames antes de invocar o DTW.

### 10.4 Inicialização Antecipada da Câmera na Splash Screen
- **Problema:** Ao entrar na tela de lição, a câmera demorava de 2 a 4 segundos para enumerar formatos no driver do sistema operacional.
- **Solução em `SplashScreen.gd`:** Adicionado o **Passo 3** na inicialização do aplicativo, disparando `CameraServer.monitoring_feeds = true` e carregando extensões nativas em segundo plano enquanto o usuário navega nos menus.

### 10.5 Visibilidade Garantida da Tela de Carregamento
- **Problema:** A leitura do JSON no cache de disco demorava apenas 109 ms, fechando o `LoadingOverlay` enquanto a tela ainda estava sob a cortina preta de fade da transição de cena (180 ms).
- **Solução em `LessonScreen.gd`:** Definido `z_index = 100` no overlay, inseridas pausas assíncronas de renderização (`await get_tree().process_frame`) entre os passos (Dados $\to$ Avatar $\to$ IA $\to$ Câmera) e delay de conclusão de 0.4s para garantir que o usuário veja a prontidão do sistema.

---

## 11. Interface de Usuário e Feedback Diagnóstico (`ComparisonCard.gd`)

Os resultados do validador paralelo são apresentados de forma rica e acolhedora no componente `ComparisonCard.gd`:

```
┌────────────────────────────────────────────────────────────────────────┐
│  Avaliação Biomecânica da Forma da Mão                                 │
│  Diagnóstico postural em tempo real com Rede Neural (Classificador TCC)│
├────────────────────────────────────────────────────────────────────────┤
│  Sinal Alvo (Gabarito): Sinal 'A'                                      │
│  Postura Reconhecida:   Sinal 'A'              [ 🎯 Postura Correta! ] │
│  Mãos Avaliadas: Ambas as Mãos (Direita + Esquerda)                    │
│    • Mão Direita: Sinal 'A' (96.5%)                                    │
│    • Mão Esquerda: Sinal 'A' (94.0%)                                   │
├────────────────────────────────────────────────────────────────────────┤
│  Diagnóstico Articular Dedo a Dedo:                                    │
│    Polegar:               ✅ Correto     Indicador:         ✅ Correto │
│    Médio:                 ✅ Correto     Anelar:            ✅ Correto │
│    Mínimo:                ✅ Correto     Abertura Dedos:    ✅ Correto │
├────────────────────────────────────────────────────────────────────────┤
│  💡 Orientações Anatômicas para Aperfeiçoamento:                       │
│    • Excelente postura! Os dedos e a abertura estão alinhados.         │
├────────────────────────────────────────────────────────────────────────┤
│  Telemetria: Confiança IA: 96.9% | Estabilidade: 72/74 | Geométrica: 88%│
└────────────────────────────────────────────────────────────────────────┘
```

1. **Banner de Correspondência:** Exibe o sinal esperado e a letra identificada, com badges coloridas (`🎯 Postura Correta!`, `⚠️ Postura Parcial`, `❌ Postura a Ajustar` ou `❌ Mão Não Detectada`).
2. **Detalhamento Bimanual:** Informa se a avaliação foi realizada com a mão direita, esquerda (canhoto) ou ambas simultaneamente.
3. **Grid Articular Dedo a Dedo:** Apresenta status individual para Polegar, Indicador, Médio, Anelar, Mínimo e Abertura Lateral, indicando com clareza quais articulações precisam de ajuste.
4. **Orientações em Linguagem Natural:** Mensagens amigáveis instruindo exatamente o movimento corretivo (ex: *"Estique o dedo INDICADOR para cima!"*, *"AFASTE o Indicador do Médio para o sinal V"*).
5. **Telemetria Técnica:** Transparência científica demonstrando a confiança da IA, a cobertura de quadros estáveis e a nota do comparador geométrico.

---

## 12. Validação Automatizada e Cobertura de Testes

Todas as funcionalidades técnicas contam com testes automatizados executados via GUT (*Godot Unit Testing*):

### 12.1 Suíte de Integração com a IA (`test_hand_ai_integration.gd`)
- `test_engine_loads_and_passes_sanity`: Valida o forward-pass do `HandNeuralEngine` contra o oráculo do TensorFlow.
- `test_biomechanical_guidance_parser`: Testa a decodificação da taxonomia de 10 dígitos.
- `test_classifier_extract_features`: Testa a normalização invariante a escala e translação.
- `test_classifier_median_filter_kills_outlier`: Valida a imunidade a oclusões rápidas de 1 frame.
- `test_dual_hand_extraction_and_model_execution`: Testa o espelhamento canônico da mão esquerda e classificação bimanual.
- `test_continuous_posture_similarity`: Valida a escala contínua de pontuação.
- `test_unread_frames_ignored_in_evaluation`: Garante que quadros sem mãos não degradam o ápice da nota.
- `test_mobile_stride_optimization`: Testa a amostragem adaptativa para celulares.
- `test_weighted_precision_70_hand_30_motion`: Valida o equilíbrio ponderado 70/30.
- `test_no_hands_detected_handling`: Garante nota zero e sem falsos positivos para mãos ausentes.
- `test_strict_shape_scoring_tolerances`: Testa a rejeição incisiva para desvios além de 2 caracteres ou erros grosseiros.
- `test_oversized_frames_safety_downsampling`: Valida a proteção algorítmica contra matrizes DTW gigantes.
- **Resultado:** **18/18 testes aprovados (100% de sucesso)**.

### 12.2 Suíte de Desempenho e Loading (`test_profiler_and_loading.gd`)
- `test_profiler_timer_and_file_logging`: Valida o registro de latência e telemetria de memória no log.
- `test_loading_overlay_lifecycle`: Testa a exibição e ciclo de vida do overlay estilizado.
- `test_lesson_service_instant_disk_cache`: Valida a recuperação em cache local instantâneo.
- `test_recording_state_waits_for_camera_before_countdown`: Garante que a contagem regressiva só inicia com quadros reais da câmera.
- `test_holistic_camera_helpers`: Testa a prontidão dos feeds e enumeração de hardware.
- **Resultado:** **5/5 testes aprovados (100% de sucesso)**.

---

## 13. Referência Rápida de Arquivos e Responsabilidades

| Componente | Caminho do Arquivo | Responsabilidade Técnica |
| :--- | :--- | :--- |
| **Validador Paralelo** | [`ParallelSignValidator.gd`](file:///c:/DevTools/Repositories/Faculdade/PENO/Scripts/ParallelSignValidator.gd) | Orquestrador híbrido, ponderação 70/30, cache de sinal base e regra de mãos ausentes. |
| **Classificador de Forma** | [`HandShapeClassifier.gd`](file:///c:/DevTools/Repositories/Faculdade/PENO/Scripts/HandShapeClassifier.gd) | Extração de features, suporte bimanual, filtro EMA/Mediana e cálculo de ápice. |
| **Motor Neural Nativo** | [`HandNeuralEngine.gd`](file:///c:/DevTools/Repositories/Faculdade/PENO/Scripts/HandNeuralEngine.gd) | Forward-pass zero-alloc em GDScript puro (42 $\to$ 512 $\to$ 256 $\to$ 128 $\to$ 2.364). |
| **Orientador Biomecânico**| [`HandBiomechanicalGuidance.gd`](file:///c:/DevTools/Repositories/Faculdade/PENO/Scripts/HandBiomechanicalGuidance.gd) | Tolerâncias estritas, cálculo de similaridade cinesiológica e geração de dicas em português. |
| **Comparador Cinemático** | [`Comparador.gd`](file:///c:/DevTools/Repositories/Faculdade/PENO/Scripts/Comparador.gd) | DTW multivariado com banda, normalização de tronco BodyFrame e OneEuroFilter. |
| **Wrapper Cinemático** | [`MotionWrapper.gd`](file:///c:/DevTools/Repositories/Faculdade/PENO/Scripts/MotionWrapper.gd) | Validador de gabarito e retentativa em espelho para canhotos. |
| **Visão Computacional** | [`HolisticLandmarker.gd`](file:///c:/DevTools/Repositories/Faculdade/PENO/GUI/vision/holistic_landmarker/HolisticLandmarker.gd) | Captura de câmera, limitador de 30 FPS, descarte por contrapressão e teto de captura. |
| **Card de Diagnóstico** | [`ComparisonCard.gd`](file:///c:/DevTools/Repositories/Faculdade/PENO/GUI/components/ComparisonCard.gd) | Apresentação visual da correspondência, grid dedo a dedo e telemetria. |
| **Pesos Binários** | [`weights.bin`](file:///c:/DevTools/Repositories/Faculdade/PENO/assets/models/weights.bin) | Pesos de ponto flutuante de 32 bits das 4 camadas densas e Batch Normalization (1.97 MB). |
| **Catálogo de Labels** | [`labels.json`](file:///c:/DevTools/Repositories/Faculdade/PENO/assets/models/labels.json) | Rótulos das 2.364 classes anatômicas DADADADAFP. |
| **Sementes Cinemáticas** | `TCC/Treinamento IA/data/seeds/seeds.json` | 2.364 sementes 3D canônicas puras podadas anatomicamente. |
| **Gerador Sintético** | `TCC/Treinamento IA/scripts/synthetic_generator.py` | Motor de aumentação em domo esférico 3D gerando 1,4M+ amostras. |
| **Pipeline de Treino** | `TCC/Treinamento IA/scripts/neural_engine.py` | Treinamento da DNN em Keras, validação (99.84%) e exportação TFLite/binários. |
