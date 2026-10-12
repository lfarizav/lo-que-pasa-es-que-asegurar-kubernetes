#!/usr/bin/env bash
# lab-part-06 - teardown
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

kind delete cluster --name cks-p06 \
  --kubeconfig "$HOME/cks-lab/p06/kubeconfig" 2>/dev/null
rm -rf "$HOME/cks-lab/p06"
echo "cluster cks-p06 eliminado y workspace ~/cks-lab/p06 borrado"
echo "ningun otro cluster, contexto ni contenedor de la maquina fue tocado"
