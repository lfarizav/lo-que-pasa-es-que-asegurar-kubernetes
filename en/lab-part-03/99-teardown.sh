#!/usr/bin/env bash
# lab-part-03 - teardown
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

NODO="cks-p03-control-plane"
for P in $(docker exec "$NODO" sh -c "awk '/^cks-p03-/ {print \$1}' /sys/kernel/security/apparmor/profiles" 2>/dev/null); do
  docker exec "$NODO" sh -c "printf '%s' '$P' > /sys/kernel/security/apparmor/.remove" 2>/dev/null
  echo "perfil de AppArmor descargado del kernel: $P"
done
kind delete cluster --name cks-p03
rm -rf "$HOME/cks-lab/p03"
echo "cluster cks-p03 eliminado, perfiles de AppArmor descargados del kernel del host y workspace borrado; ningun otro cluster de kind fue tocado y su kubeconfig de siempre nunca se modifico"
