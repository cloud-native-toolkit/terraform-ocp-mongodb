#!/usr/bin/env bash

SANAME="$1"
NAMESPACE="$2"
CHARTS_DIR=$(cd $(dirname $0)/../charts; pwd -P)

if [[ "$3" == "destroy" ]]; then
    echo "removing chart extension..."
    # remove the the operator 
    kubectl delete Deployment ${SANAME} -n ${NAMESPACE}
else
# create the operator 
cat > "${CHARTS_DIR}/operator.yaml" << EOL
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    email: support@mongodb.com
  labels:
    owner: mongodb
  name: ${SANAME}
  namespace: "${NAMESPACE}"
spec:
  replicas: 1
  selector:
    matchLabels:
      name: ${SANAME}
  strategy:
    rollingUpdate:
      maxUnavailable: 1
    type: RollingUpdate
  template:
    metadata:
      labels:
        name: ${SANAME}
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: name
                operator: In
                values:
                - ${SANAME}
            topologyKey: kubernetes.io/hostname
      containers:
      - command:
        - /usr/local/bin/entrypoint
        env:
        - name: WATCH_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: OPERATOR_NAME
          value: ${SANAME}
        - name: AGENT_IMAGE
          value: quay.io/mongodb/mongodb-agent:11.0.5.6963-1
        - name: VERSION_UPGRADE_HOOK_IMAGE
          value: quay.io/mongodb/${SANAME}-version-upgrade-post-start-hook:1.0.2
        - name: READINESS_PROBE_IMAGE
          value: quay.io/mongodb/mongodb-kubernetes-readinessprobe:1.0.4
        - name: MONGODB_IMAGE
          value: mongo
        - name: MONGODB_REPO_URL
          value: docker.io
        image: quay.io/mongodb/mongodb-kubernetes-operator:0.7.0
        imagePullPolicy: Always
        name: ${SANAME}
        resources:
          limits:
            cpu: 1100m
            memory: 1Gi
          requests:
            cpu: 500m
            memory: 200Mi
        securityContext:
          readOnlyRootFilesystem: true
          runAsUser: 2000
      serviceAccountName: ${SANAME}
EOL
    kubectl create -f "${CHARTS_DIR}/operator.yaml" -n ${NAMESPACE}
fi
