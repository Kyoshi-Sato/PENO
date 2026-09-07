#!/usr/bin/env python3
"""Monta o bundle holístico que o app carrega, a partir dos oficiais do MediaPipe.

O .task é só um zip de .tflite, e reempacotá-lo resolve duas coisas que o
bundle de fábrica não deixa escolher:

  1. O holistic_landmarker.task traz o pose_landmarks_detector LITE
     (2.818.358 bytes — o mesmo do pose_landmarker_lite.task). Trocar o
     arquivo por full ou heavy funciona: as três são variantes com a mesma
     assinatura de tensores, e o grafo inicializa e roda.
  2. Ele traz face_detector + face_landmarks_detector + face_blendshapes
     (~2,3 MB) que este app nunca consome. Como não conectamos as saídas
     FACE, a HolisticLandmarkerGraph nem monta esse ramo — verificado: o
     grafo inicializa com o bundle sem esses três arquivos. Se o ramo fosse
     montado, falharia ao extraí-los do bundle ao gerar a config.

As entradas precisam ficar STORED. O MediaPipe mapeia os modelos direto do
arquivo; com deflate o `initialize` devolve false. (O ZIPPacker da Godot só
escreve deflate — por isso esta ferramenta é Python e não .gd.)

Uso:
    python3 tools/montar_bundle_holistico.py --pose full
    python3 tools/montar_bundle_holistico.py --pose heavy --com-face
    python3 tools/montar_bundle_holistico.py --pose lite --com-face   # volta ao de fábrica

Os bundles de origem são baixados sob demanda para tools/.cache_mediapipe/.
"""

import argparse
import pathlib
import sys
import urllib.request
import zipfile

BASE = "https://storage.googleapis.com/mediapipe-models"
RAIZ = pathlib.Path(__file__).resolve().parent.parent
CACHE = RAIZ / "tools" / ".cache_mediapipe"
DESTINO = RAIZ / "assets" / "mediapipe" / "holistic_landmarker.task"

POSE_ENTRY = "pose_landmarks_detector.tflite"
FACE_ENTRIES = (
    "face_detector.tflite",
    "face_landmarks_detector.tflite",
    "face_blendshapes.tflite",
)

ORIGENS = {
    "holistic": "holistic_landmarker/holistic_landmarker/float16/latest/holistic_landmarker.task",
    "lite": "pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task",
    "full": "pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task",
    "heavy": "pose_landmarker/pose_landmarker_heavy/float16/latest/pose_landmarker_heavy.task",
}


def baixar(chave: str) -> pathlib.Path:
    destino = CACHE / (chave + ".task")
    if destino.exists():
        return destino
    CACHE.mkdir(parents=True, exist_ok=True)
    url = f"{BASE}/{ORIGENS[chave]}"
    print(f"baixando {chave}... ", end="", flush=True)
    urllib.request.urlretrieve(url, destino)
    print(f"{destino.stat().st_size} bytes")
    return destino


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--pose", choices=("lite", "full", "heavy"), default="full",
                   help="variante do pose_landmarks_detector (padrão: full)")
    p.add_argument("--com-face", action="store_true",
                   help="mantém os modelos de face (o app não os usa)")
    args = p.parse_args()

    base = zipfile.ZipFile(baixar("holistic"))
    pose_novo = None
    if args.pose != "lite":
        pose_novo = zipfile.ZipFile(baixar(args.pose)).read(POSE_ENTRY)

    total = 0
    DESTINO.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(DESTINO, "w", zipfile.ZIP_STORED) as saida:
        for info in base.infolist():
            if not args.com_face and info.filename in FACE_ENTRIES:
                print(f"  - {info.filename} (removido)")
                continue
            dados = (pose_novo if info.filename == POSE_ENTRY and pose_novo
                     else base.read(info.filename))
            saida.writestr(info.filename, dados)
            total += len(dados)
            print(f"  + {info.filename:<34} {len(dados):>9} bytes")

    face = "sim" if args.com_face else "não"
    print(f"\n{DESTINO.relative_to(RAIZ)}  (pose={args.pose}, face={face})"
          f"  {DESTINO.stat().st_size} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
