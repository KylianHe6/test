#!/bin/bash
set -eux

export AWS_PROFILE=${aws_profile}
aws eks --region ${aws_region} update-kubeconfig --name ${cluster_name} --alias ${cluster_name} && \
kubectl config use-context ${cluster_name} && \
kubectl annotate sc gp2 storageclass.kubernetes.io/is-default-class- && \
kubectl -n kube-system patch daemonset aws-node   --type='strategic' -p='{"spec":{"template":{"spec":{"nodeSelector":{"io.cilium/aws-node-enabled":"true"}}}}}'