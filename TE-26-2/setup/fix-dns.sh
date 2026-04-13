#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CLUSTER_NAME="demo"
source "${SCRIPT_DIR}/jozu-hub-product/tools/local-dev/global.sh"

if [ "$(uname)" == "Darwin" ]; then
  IP_ADDR="$(ipconfig getifaddr en0)"
  if [ -z "$IP_ADDR" ]; then
    IP_ADDR="$(ipconfig getifaddr en1)"
  fi
else
  IP_ADDR=$(hostname -I | cut -f 1 -d ' ')
fi

echo "Updating CoreDNS to resolve *.${CLUSTER_URL} to ${IP_ADDR}"

cat <<EOF | kubectl apply --server-side --force-conflicts -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
      errors
      health {
        lameduck 5s
      }
      ready
      kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
        ttl 30
      }
      prometheus :9153
      template IN A {
        match ${CLUSTER_URL}
        answer "{{ .Name }} 60 IN A ${IP_ADDR}"
        fallthrough
      }
      forward . /etc/resolv.conf {
        max_concurrent 1000
      }
      cache 30
      loop
      reload
      loadbalance
    }
EOF

kubectl delete pod -l k8s-app=kube-dns -n kube-system

echo "Updating /etc/hosts..."
"${SCRIPT_DIR}/jozu-hub-product/tools/local-dev/setup-local-dns.sh" update

echo "DNS updated."
