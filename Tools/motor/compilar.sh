#!/usr/bin/env bash
# Compila o editor e os templates da Godot 4.7.1 "spolia" (pacote cifrado do
# nosso jeito + tokenizador embaralhado) para o PENO.
#
# Uso: Tools/motor/compilar.sh [editor] [linux] [android]   (sem argumentos: todos)
#
# Fonte em ~/godot-src-spolia (worktree de ~/godot-src na tag 4.7.1-stable +
# godot-4.7-spolia.patch). Segredo em
# ~/.config/falsecontinuum/motor_segredo.json (Tools/motor/segredo.py).
#
# O editor gera o .pck cifrado no export; os templates (linux/android) o leem
# em runtime. Os dois têm de sair do mesmo segredo. Depois de compilar, rode
# `segredo.py credenciais` para gravar a chave nos presets do PENO e aponte os
# custom_template dos presets Linux/Android para os binários gerados aqui.
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
PROJETO="$(cd "$AQUI/../.." && pwd)"
GODOT="${GODOT_FONTE:-$HOME/godot-src-spolia}"
GODOT_LIMPO="${GODOT_LIMPO:-$HOME/godot-src}"
TEMPLATES="$HOME/.local/share/godot/export_templates/4.7.1.spolia"
JOBS="${JOBS:-10}"
MEMORIA="${MEMORIA:-9G}"

# SDK/NDK do Android (mesma toolchain que compilou o template atual do PENO).
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -1)}"

# Fonte: um worktree 4.7.1 separado do ~/godot-src (que fica como fallback limpo).
if [ ! -d "$GODOT/.git" ] && [ ! -f "$GODOT/.git" ]; then
	if [ -d "$GODOT_LIMPO/.git" ]; then
		git -C "$GODOT_LIMPO" worktree add --detach "$GODOT" 4.7.1-stable
	else
		git clone --depth 1 --branch 4.7.1-stable https://github.com/godotengine/godot.git "$GODOT"
	fi
fi
if ! grep -q "ProjectSpolia" "$GODOT/core/io/file_access_encrypted.cpp"; then
	git -C "$GODOT" apply "$AQUI/godot-4.7-spolia.patch"
fi

python3 "$AQUI/segredo.py" gerar
python3 "$AQUI/segredo.py" cabecalho "$GODOT"
CHAVE="$(python3 "$AQUI/segredo.py" chave)"

# O status entra na versão/pasta de templates; os presets apontam para os
# custom_template absolutos gerados aqui, então não dependemos do lookup.
export GODOT_VERSION_STATUS=spolia
# Sem accesskit (leitor de tela): o SDK dele não vem com a fonte.
COMUM=(production=yes lto=none debug_symbols=no accesskit=no "-j$JOBS")

scons_teto() {
	# O registro de módulos é um arquivo só para editor, debug e release; sobra
	# do alvo anterior e o release linka módulos que não tem (objectdb_profiler).
	rm -f "$GODOT"/modules/register_module_types.gen.cpp "$GODOT"/bin/obj/modules/register_module_types.gen.*.o
	# Teto de memória: um build sem limite já derrubou esta máquina.
	systemd-run --user --scope -q -p MemoryMax="$MEMORIA" -p MemorySwapMax=0 \
		scons -C "$GODOT" "$@"
}

alvos=("$@")
[ ${#alvos[@]} -eq 0 ] && alvos=(editor linux android)
mkdir -p "$TEMPLATES"

for alvo in "${alvos[@]}"; do
	case "$alvo" in
	editor)
		# O editor não leva chave: usa a do preset na hora de exportar. Só roda
		# aqui, então dispensa o libstdc++ estático.
		SCRIPT_AES256_ENCRYPTION_KEY="" scons_teto platform=linuxbsd target=editor use_static_cpp=no "${COMUM[@]}"
		mkdir -p "$HOME/.local/bin"
		ln -sf "$GODOT/bin/godot.linuxbsd.editor.x86_64" "$HOME/.local/bin/godot-spolia"
		;;
	linux)
		# Templates com libstdc++ estático para rodar em outras distros.
		for t in template_release template_debug; do
			SCRIPT_AES256_ENCRYPTION_KEY="$CHAVE" scons_teto platform=linuxbsd target=$t "${COMUM[@]}"
		done
		cp "$GODOT/bin/godot.linuxbsd.template_release.x86_64" "$TEMPLATES/linux_release.x86_64"
		cp "$GODOT/bin/godot.linuxbsd.template_debug.x86_64" "$TEMPLATES/linux_debug.x86_64"
		;;
	android)
		# O PENO exporta só arm64-v8a (ver export_presets.cfg). O template é stock:
		# GDMP/CameraServer entram como .so de GDExtension no próprio export, não no
		# template. Monta os APKs-template pré-compilados (use_gradle_build=false).
		[ -n "$ANDROID_NDK_ROOT" ] || { echo "NDK não encontrado em $ANDROID_HOME/ndk" >&2; exit 1; }
		for t in template_release template_debug; do
			SCRIPT_AES256_ENCRYPTION_KEY="$CHAVE" scons_teto platform=android target=$t arch=arm64 "${COMUM[@]}"
		done
		# Monta bin/android_{debug,release}.apk + android_source.zip via gradle.
		# O lint do AGP não encerra no JDK 25 do sistema ("Failed to stop
		# LintClassLoaderBuildService"); o gradle roda num JDK 21 à parte.
		JH_GRADLE="${JAVA_HOME_GRADLE:-$(ls -d "$HOME"/jdk-para-gradle/jdk-21*/ 2>/dev/null | head -1)}"
		[ -x "$JH_GRADLE/bin/java" ] || { echo "JDK 21 p/ gradle não encontrado em ~/jdk-para-gradle; baixe um antes" >&2; exit 1; }
		( cd "$GODOT/platform/android/java" && JAVA_HOME="$JH_GRADLE" PATH="$JH_GRADLE/bin:$PATH" ./gradlew generateGodotTemplates )
		cp "$GODOT/bin/android_release.apk" "$TEMPLATES/android_release.apk"
		cp "$GODOT/bin/android_debug.apk" "$TEMPLATES/android_debug.apk"
		cp "$GODOT/bin/android_source.zip" "$TEMPLATES/android_source.zip"
		;;
	*)
		echo "alvo desconhecido: $alvo" >&2
		exit 1
		;;
	esac
done

echo "4.7.1.spolia" >"$TEMPLATES/version.txt"
echo "pronto: editor em ~/.local/bin/godot-spolia, templates em $TEMPLATES"
