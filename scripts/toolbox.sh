#!/bin/bash

pod=$(kubectl get pods -n rook-ceph -l app.kubernetes.io/name=toolbox -o jsonpath='{.items[0].metadata.name}')
if [ -n "$pod" ]; then
    echo "Pod '${pod}' found; starting Rook Ceph Toolbox."
    kubectl -n rook-ceph exec -it $pod -- bash
else
    echo "Cannot start Rook Ceph Toolbox; no pods found."ß
fi
