#!/bin/bash
set -eux

git clone https://github.com/kubernetes-csi/external-snapshotter.git --depth 1
kubectl config use-context ${cluster_name} && \
kubectl kustomize external-snapshotter/client/config/crd | kubectl create -f - && \
kubectl -n kube-system kustomize external-snapshotter/deploy/kubernetes/snapshot-controller | kubectl create -f -
# kubectl kustomize external-snapshotter/deploy/kubernetes/csi-snapshotter | kubectl create -f -
rm -rf external-snapshotter