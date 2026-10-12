#!/usr/bin/env bash
# lab-part-01 step 4 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/cks-lab/p01/binario
K="kubectl --kubeconfig $HOME/cks-lab/p01/kubeconfig"

# 1. La version NO se escribe de memoria: se le pregunta al cluster.
$K get --raw /version; echo
MAJOR=$($K get --raw /version | sed -n 's/.*"major": *"\([^"]*\)".*/\1/p')
MINOR=$($K get --raw /version | sed -n 's/.*"minor": *"\([^"]*\)".*/\1/p')
echo "este cluster es de la linea $MAJOR.$MINOR"

# 2. La ultima version estable de ESA linea, dicha por el proyecto.
VERSION=$(curl -sSL "https://dl.k8s.io/release/stable-$MAJOR.$MINOR.txt")
echo "la ultima estable de la linea $MAJOR.$MINOR es $VERSION"

# 3. El binario Y su suma oficial, del mismo sitio del proyecto.
curl -sSLO "https://dl.k8s.io/release/$VERSION/bin/linux/amd64/kubectl"
curl -sSLO "https://dl.k8s.io/release/$VERSION/bin/linux/amd64/kubectl.sha256"
ls -l kubectl kubectl.sha256
cat kubectl.sha256; echo

# 4. La revision del carne. sha256sum --check quiere el formato
#    "<suma><dos espacios><archivo>", asi que se arma el archivo primero.
echo "$(cat kubectl.sha256)  kubectl" > SUMA-OFICIAL.txt
sha256sum --check SUMA-OFICIAL.txt
echo "resultado del original: $?"

# 5. Ahora la parte que de verdad ensena: un solo byte cambiado.
cp kubectl kubectl-adulterado
printf 'X' | dd of=kubectl-adulterado bs=1 seek=1000000 conv=notrunc status=none
ls -l kubectl kubectl-adulterado
echo "$(cat kubectl.sha256)  kubectl-adulterado" > SUMA-ADULTERADA.txt
sha256sum --check SUMA-ADULTERADA.txt
echo "resultado del adulterado: $?"

# 6. Recien ahora se le da permiso de ejecucion, y se le pregunta quien es.
chmod +x kubectl
./kubectl version --client

cd ~/cks-lab/p01
# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/cks-lab/p01"
B="$D/binario"
( cd "$B" && sha256sum --check SUMA-OFICIAL.txt >/dev/null 2>&1 ) && R1=OK || R1=FALLA
( cd "$B" && sha256sum --check SUMA-ADULTERADA.txt >/dev/null 2>&1 ) && R2=OK || R2=FALLA
cat > "$D/04-respuesta.txt" <<RESP
VERSION_DESCARGADA=$VERSION
SHA256_OFICIAL=$(tr -d '[:space:]' < "$B/kubectl.sha256")
RESULTADO_ORIGINAL=$R1
RESULTADO_ADULTERADO=$R2
RESP
cat "$D/04-respuesta.txt"
