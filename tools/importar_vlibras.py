#!/usr/bin/env python3
"""Converte um sinal do dicionário VLibras em uma Animation .tres do Godot.

    python3 tools/importar_vlibras.py CASA OBRIGADO --saida assets/animacoes/

PROCEDÊNCIA
-----------
Os sinais vêm do dicionário oficial do VLibras (LAViD/UFPB + Governo Federal),
o mesmo que o widget de acessibilidade do gov.br usa em produção:

    https://dicionario2.vlibras.gov.br/static/BUNDLES/2018.3.1/WEBGL/BR/<GLOSA>

Cada resposta é um AssetBundle do Unity 2018.3.1 (`UnityFS`) contendo UM
AnimationClip legacy, não comprimido, a 30 fps: 84 curvas de rotação, 84 de
posição, 84 de escala e 22 de blend shape facial. Como é legacy, as curvas
guardam o caminho do osso em TEXTO — daí a conversão ser transcrição de
formato, e não engenharia reversa.

O uso é livre para fins não eleitorais e não comerciais, conforme resposta da
equipe do VLibras. Cite a fonte em qualquer trabalho derivado.

A CONVERSÃO DE EIXOS
--------------------
Unity é canhoto (Y para cima); Godot é destro; e o rig nasceu no Blender, que
é Z para cima.

    Para todo osso:   (x, y, z, w)  ->  (x, -y, -z, w)

Calibrado contra o rest do esqueleto do VLibras: das 63 curvas constantes do
clipe CENOURA, 50 caem em cima do rest com erro 0,00°. (As que não caem são o
braço esquerdo: num sinal de uma mão só, o animador abaixa o braço
não-dominante e o segura ali — aquela constante é uma pose, não o rest.)

OS OSSOS DE RAIZ SÃO DESCARTADOS
--------------------------------
Os 7 ossos que pendem direto do nó `Armature.001` — `BnBacia.001`, os dois
`ik_FK`, os dois `BnPolyV` e os dois `BnMaoOrient` — não recebem track.

O motivo é que eles carregam a conversão Z-para-cima do Blender, e ela é
DIFERENTE em cada rig, porque depende de como o esqueleto foi importado:

    rest do BnBacia.001 no rig do VLibras (via glTF) .... -90° em X
    rest do BnBacia.001 no rig Libra deste projeto ...... +90° em X

Escrever um valor fixo acerta num e erra 180° no outro — foi o que deixou o
personagem deitado. E não há o que ganhar acertando: nenhum deles carrega
informação do sinal (a bacia não se mexe; ik_FK, BnPolyV e BnMaoOrient são
controles de animação do Blender, inertes no Godot). Sem track, cada osso fica
no rest do SEU rig, que é o certo em ambos.

É também o que o gabarito `ABACAXI.tres` deste projeto faz: ele não tem track
para nenhum dos sete.

QUANDO NÃO USAR ESTA FERRAMENTA  (leia antes)
---------------------------------------------
Se você tem o `.blend` do sinal, NÃO use isto. Faça "append" da action no seu
arquivo do Blender: funciona melhor, e a razão é de formato, não de esforço.

    Blender guarda a rotação de um pose bone como DELTA em relação ao rest,
    no espaço local do próprio osso. Delta não sabe nada sobre o rest do
    destino — por isso a action cai certa em qualquer rig com os mesmos
    nomes de osso, mesmo com proporções e rest diferentes.

    Unity (nos bundles) e Godot (nas tracks rotation_3d) guardam a rotação
    local ABSOLUTA, que é rest ∘ delta. Ela carrega o rest do rig de origem
    junto, e por isso só está certa no rig em que foi autorada.

Ou seja: o append transporta o gesto; esta ferramenta transporta o gesto MAIS
o rest do esqueleto do VLibras. No rig do VLibras isso dá no mesmo. Em
qualquer outro, não.

Tentei desfazer isso extraindo o delta (`L · U⁻¹ · M(q)`, com U = rest do
VLibras e L = rest do destino) e o erro PIOROU, de 9,5° para 27,4° de média
contra o gabarito que funciona. O motivo é que não temos o U verdadeiro: o
rest que dá para ler do glTF é o que o importador do Godot produziu, e o
importador do Unity atribui outros eixos locais aos mesmos ossos. Sem o rest
do lado do Unity, o delta não é recuperável a partir do bundle.

LIMITE CONHECIDO

RETARGET PARA O RIG LIBRA
-------------------------
O acima entrega a animação para o ESQUELETO DO VLIBRAS. O rig `Libra` deste
projeto é um derivado com rest diferente em 15 dos 47 ossos (mão 121°, ombro
direito 90°, dedos de 4,8° a 25,2°), e nele a animação sai torta.

Tentei derivar o retarget dos rest poses — L·V-1, V-1·L, L-1·V, V·L-1, nas duas
ordens de multiplicação. Nenhuma reproduz a correção observada: a melhor acerta
20 dos 47 ossos. O rest do rig VLibras importado no Godot não está na mesma
convenção em que as curvas do bundle foram autoradas, e eu não fechei essa
conta analiticamente.

O que funciona é medir. Existe um par com gabarito: o `ABACAXI.tres` deste
repositório é um retarget CORRETO do bundle ABACAXI — é a animação que roda
hoje. Comparando os dois osso a osso, a correção é uma rotação CONSTANTE por
osso, que é o palpite certo: a diferença entre os rigs é de rest, não de
movimento.

    correcao[osso] = q_gabarito * inverso(q_convertido)      (pré-multiplicação)

Validação em sinal SEPARADO (ABACATE, não usado para derivar a tabela):

    sem correção ..... mediana 1,77°   p90 14,91°   máx 90,67°
    com a tabela ..... mediana 1,63°   p90  4,54°   máx 13,24°

Os 13° do pior caso vêm em boa parte da reamostragem: o gabarito tem 10
keyframes onde o bundle tem 4, então nem todo "mesmo tempo" compara valores
originais. Refaça a tabela com --calibrar se trocar de rig.

"""

import argparse
import json
import math
import os
import sys
import urllib.parse
import urllib.request

BASE = "https://dicionario2.vlibras.gov.br/static/BUNDLES/2018.3.1/WEBGL"
REGIAO_PADRAO = "BR"
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cache_vlibras")

## Prefixo do NodePath de cada track. Precisa casar com a cena do avatar:
## o AnimationPlayer resolve as tracks a partir do seu `root_node`.
ESQUELETO_PADRAO = "Armature_002/Skeleton3D"

## Tabela de retarget por osso do rig `Libra`. Ver "RETARGET PARA O RIG LIBRA".
CORRECAO_LIBRA = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                              "vlibras_correcao_libra.json")

## Godot interpola quaternion com slerp quando interp = 1 (linear).
INTERP_LINEAR = 1


def baixar(glosa, regiao=REGIAO_PADRAO):
    """Baixa o bundle da glosa, com cache em disco.

    O cache não é otimização: é educação. Reconverter mil vezes durante o
    desenvolvimento não deve virar mil requisições ao servidor de um serviço
    público de acessibilidade.
    """
    os.makedirs(CACHE, exist_ok=True)
    destino = os.path.join(CACHE, "%s_%s" % (regiao, glosa))
    if os.path.exists(destino) and os.path.getsize(destino) > 0:
        return destino

    url = "%s/%s/%s" % (BASE, regiao, urllib.parse.quote(glosa))
    req = urllib.request.Request(url, headers={"User-Agent": "PENO-TCC/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        dados = r.read()
    if not dados.startswith(b"UnityFS"):
        raise RuntimeError("%s: resposta não é um AssetBundle (%d bytes)"
                           % (glosa, len(dados)))
    with open(destino, "wb") as f:
        f.write(dados)
    return destino


def ler_clip(caminho):
    import UnityPy
    env = UnityPy.load(caminho)
    clips = [o.read() for o in env.objects if o.type.name == "AnimationClip"]
    if not clips:
        raise RuntimeError("%s: nenhum AnimationClip no bundle" % caminho)
    return clips[0]


## Nome do nó de armature nos caminhos das curvas do bundle. Um osso cujo
## caminho é "<ARMATURE>/<osso>" é osso de raiz e leva a correção.
ARMATURE = "Armature.001"


def multiplicar(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz)


def converter_quaternion(q, converter=True):
    """Unity -> Godot. Ver 'A CONVERSÃO DE EIXOS' no topo."""
    if not converter:
        return (q.x, q.y, q.z, q.w)
    return (q.x, -q.y, -q.z, q.w)


def osso_de(caminho_unity):
    """'Armature.001/BnBacia.001/BnCol-01' -> 'BnCol-01'."""
    return str(caminho_unity).split("/")[-1]


def e_osso_raiz(caminho_unity):
    """True quando o osso pende direto do nó da armature — ver o cabeçalho:
    estes são descartados porque a conversão que carregam depende do rig."""
    partes = str(caminho_unity).split("/")
    return len(partes) <= 2


def carregar_correcao(caminho):
    if not caminho:
        return {}
    with open(caminho, encoding="utf-8") as f:
        return {k: tuple(v) for k, v in json.load(f).items()}


def calibrar(clip, caminho_tres):
    """Deriva a tabela de retarget comparando com um .tres sabidamente certo.

    A correção de cada osso é a média dos quaterniões medidos em todos os
    keyframes de tempo coincidente, com os sinais alinhados ao primeiro: q e
    -q são a mesma rotação, e somar sem alinhar cancelaria os dois.
    """
    import re
    with open(caminho_tres, encoding="utf-8") as f:
        txt = f.read()
    tipos = {int(m.group(1)): m.group(2)
             for m in re.finditer(r'tracks/(\d+)/type = "([^"]+)"', txt)}
    paths = {int(m.group(1)): m.group(2) for m in re.finditer(
        r'tracks/(\d+)/path = NodePath\("[^:]*:([^"]+)"\)', txt)}
    keys = {int(m.group(1)): [float(x) for x in m.group(2).split(",")]
            for m in re.finditer(
                r'tracks/(\d+)/keys = PackedFloat32Array\(([^)]*)\)', txt)}
    alvo = {}
    for i, nome in paths.items():
        if tipos.get(i) != "rotation_3d":
            continue
        ks = keys[i]
        alvo[nome] = {round(ks[j * 6], 4): tuple(ks[j * 6 + 2:j * 6 + 6])
                      for j in range(len(ks) // 6)}

    fonte = {}
    for c in clip.m_RotationCurves:
        nome = osso_de(c.path)
        if nome != ARMATURE:
            fonte[nome] = {round(k.time, 4): converter_quaternion(k.value)
                           for k in c.curve.m_Curve}

    tabela = {}
    for osso, kv in alvo.items():
        medidas = []
        for tempo, alvo_q in kv.items():
            origem = fonte.get(osso, {}).get(tempo)
            if origem is not None:
                medidas.append(multiplicar(
                    alvo_q, (-origem[0], -origem[1], -origem[2], origem[3])))
        if not medidas:
            continue
        ref = medidas[0]
        acc = [0.0] * 4
        for q in medidas:
            if sum(q[i] * ref[i] for i in range(4)) < 0:
                q = tuple(-c for c in q)
            for i in range(4):
                acc[i] += q[i]
        norma = math.sqrt(sum(a * a for a in acc)) or 1.0
        tabela[osso] = [a / norma for a in acc]
    return tabela


def tres(clip, esqueleto, ossos_permitidos=None, converter=True, correcao=None):
    """Monta o texto do .tres. Só tracks de rotação.

    Posição e escala ficam de fora de propósito: medindo o clip de ABACAXI,
    0 de 84 curvas de escala e apenas 9 de 84 de posição têm movimento real —
    o resto são constantes que só repetiriam o rest e brigariam com ele se o
    esqueleto de destino tiver proporções diferentes.
    """
    linhas = ['[gd_resource type="Animation" format=3]', "", "[resource]",
              'resource_name = "%s"' % clip.m_Name]

    tracks = []
    duracao = 0.0
    for curva in clip.m_RotationCurves:
        nome = osso_de(curva.path)
        # O nó da armature também tem curva, mas não é osso: emiti-lo criaria
        # uma track apontando para um "osso" inexistente. A rotação dele é a
        # conversão Z-para-cima do Blender, que na cena do Godot já vive no
        # transform do próprio nó Armature.
        if nome == ARMATURE or e_osso_raiz(curva.path):
            continue
        if ossos_permitidos is not None and nome not in ossos_permitidos:
            continue
        chaves = curva.curve.m_Curve
        if not chaves:
            continue
        ajuste = (correcao or {}).get(nome)
        valores = []
        for k in chaves:
            q = converter_quaternion(k.value, converter)
            if ajuste is not None:
                q = multiplicar(ajuste, q)
            x, y, z, w = q
            # Formato do Godot para rotation_3d: tempo, transição, x, y, z, w
            valores.extend([k.time, 1.0, x, y, z, w])
            duracao = max(duracao, k.time)
        tracks.append((nome, valores))

    linhas.append("length = %.7f" % duracao)
    linhas.append("loop_mode = 0")
    linhas.append("step = %.7f" % (1.0 / float(clip.m_SampleRate or 30.0)))

    for i, (nome, valores) in enumerate(tracks):
        linhas += [
            'tracks/%d/type = "rotation_3d"' % i,
            "tracks/%d/imported = true" % i,
            "tracks/%d/enabled = true" % i,
            'tracks/%d/path = NodePath("%s:%s")' % (i, esqueleto, nome),
            "tracks/%d/interp = %d" % (i, INTERP_LINEAR),
            "tracks/%d/loop_wrap = true" % i,
            "tracks/%d/keys = PackedFloat32Array(%s)" % (
                i, ", ".join("%.8g" % v for v in valores)),
        ]
    return "\n".join(linhas) + "\n", len(tracks), duracao


def carregar_lista_ossos(caminho):
    """Lê os nomes de osso de uma cena .tscn do Godot, para filtrar tracks
    que o esqueleto de destino não tem (elas seriam ignoradas em silêncio)."""
    import re
    with open(caminho, encoding="utf-8") as f:
        texto = f.read()
    return set(re.findall(r'^bones/\d+/name = "([^"]+)"', texto, re.M))


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("glosas", nargs="*", help="glosas a converter (ex.: CASA OBRIGADO)")
    p.add_argument("--saida", default=".", help="diretório de saída dos .tres")
    p.add_argument("--regiao", default=REGIAO_PADRAO)
    p.add_argument("--esqueleto", default=ESQUELETO_PADRAO,
                   help="prefixo do NodePath das tracks (default: %s)" % ESQUELETO_PADRAO)
    p.add_argument("--ossos-de", metavar="CENA.tscn",
                   help="filtra tracks pelos ossos existentes nesta cena")
    p.add_argument("--correcao", metavar="TABELA.json", nargs="?",
                   const=CORRECAO_LIBRA, default=None,
                   help="retarget por osso; sem valor, usa a tabela do rig Libra")
    p.add_argument("--calibrar", metavar="GLOSA=REFERENCIA.tres",
                   help="deriva a tabela a partir de um .tres correto e sai")
    p.add_argument("--sem-conversao", action="store_true",
                   help="não aplica a conversão de eixos (para depuração)")
    args = p.parse_args()

    try:
        import UnityPy  # noqa: F401
    except ImportError:
        sys.exit("UnityPy não instalado.  pip install UnityPy")

    if args.calibrar:
        glosa, _, referencia = args.calibrar.partition("=")
        tabela = calibrar(ler_clip(baixar(glosa, args.regiao)), referencia)
        destino = args.correcao or CORRECAO_LIBRA
        with open(destino, "w", encoding="utf-8") as f:
            json.dump(tabela, f, indent=1)
        print("tabela de retarget: %d ossos -> %s" % (len(tabela), destino))
        return

    if not args.glosas:
        p.error("informe ao menos uma glosa (ou use --calibrar)")

    tabela = carregar_correcao(args.correcao)
    if tabela:
        print("retarget: %d ossos" % len(tabela))
    permitidos = carregar_lista_ossos(args.ossos_de) if args.ossos_de else None
    if permitidos:
        print("filtro: %d ossos lidos de %s" % (len(permitidos), args.ossos_de))
    os.makedirs(args.saida, exist_ok=True)

    for glosa in args.glosas:
        try:
            bundle = baixar(glosa, args.regiao)
            clip = ler_clip(bundle)
            texto, n, dur = tres(clip, args.esqueleto, permitidos,
                                 not args.sem_conversao, tabela)
            destino = os.path.join(args.saida, "%s.tres" % glosa)
            with open(destino, "w", encoding="utf-8") as f:
                f.write(texto)
            print("  %-14s %2d tracks  %5.2f s  -> %s" % (glosa, n, dur, destino))
        except Exception as e:
            print("  %-14s FALHOU: %s" % (glosa, e))


if __name__ == "__main__":
    main()
