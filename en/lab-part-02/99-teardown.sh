#!/usr/bin/env bash
# lab-part-02 - teardown
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

kind delete cluster --name cks-p02
rm -rf "$HOME/cks-lab/p02"
echo "cluster cks-p02 eliminado y workspace borrado; ningun otro cluster de kind fue tocado y su kubeconfig de siempre nunca se modifico"
