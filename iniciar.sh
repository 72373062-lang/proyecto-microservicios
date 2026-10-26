#!/usr/bin/env bash
set -Eeuo pipefail

NAMESPACE="microservicios"
SERVICES=(usuarios productos pedidos)
LOCAL_PORTS=(3101 3102 3103)
TARGET_PORTS=(3001 3002 3003)

# Detener accesos anteriores
stop_forwarders() {
  local service pidfile pid
  for service in "${SERVICES[@]}"; do
    pidfile="/tmp/minikube-${service}-port-forward.pid"
    if [[ -f "$pidfile" ]]; then
      pid="$(cat "$pidfile" 2>/dev/null || true)"
      if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null || true
      fi
      rm -f "$pidfile"
    fi
  done
}

# Mantener el acceso activo aunque se reinicie un pod
start_forwarder() {
  local service="$1"
  local local_port="$2"
  local target_port="$3"
  local pidfile="/tmp/minikube-${service}-port-forward.pid"

  (
    child=""
    stop_child() {
      trap - TERM INT
      if [[ -n "$child" ]]; then
        kill -TERM "$child" 2>/dev/null || true
        wait "$child" 2>/dev/null || true
      fi
      exit 0
    }
    trap stop_child TERM INT

    while true; do
      kubectl port-forward \
        --address 127.0.0.1 \
        -n "$NAMESPACE" \
        "svc/$service" \
        "${local_port}:${target_port}" &
      child=$!
      wait "$child" || true
      child=""
      sleep 2
    done
  ) >"/tmp/${service}-port-forward.log" 2>&1 &

  echo "$!" >"$pidfile"
}

# Modo de funcionamiento
case "${1:-start}" in
  start)
    ;;
  stop)
    stop_forwarders
    if minikube status >/dev/null 2>&1; then
      minikube stop
    else
      echo "Minikube ya estaba detenido."
    fi
    exit 0
    ;;
  *)
    echo "Uso: $0 [start|stop]"
    exit 2
    ;;
esac

# Verificar herramientas instaladas
command -v minikube >/dev/null || { echo "Error: falta instalar Minikube."; exit 1; }
command -v kubectl >/dev/null || { echo "Error: falta instalar kubectl."; exit 1; }

# Iniciar Minikube
stop_forwarders
minikube start --driver=docker

# Comprobar que el despliegue de Kubernetes ya existe
kubectl get namespace "$NAMESPACE" >/dev/null
for service in "${SERVICES[@]}"; do
  kubectl get service "$service" -n "$NAMESPACE" >/dev/null
done

# Esperar a que los pods estén listos
if ! kubectl wait --for=condition=Ready pod --all -n "$NAMESPACE" --timeout=180s; then
  echo "Error: hay pods que no están listos."
  echo "Comprueba con: kubectl get pods -n $NAMESPACE"
  exit 1
fi

# Abrir los tres accesos
for i in "${!SERVICES[@]}"; do
  start_forwarder "${SERVICES[$i]}" "${LOCAL_PORTS[$i]}" "${TARGET_PORTS[$i]}"
done

# Esperar a que los accesos estén disponibles
for intento in {1..15}; do
  disponibles=0
  for i in "${!SERVICES[@]}"; do
    if grep -Fq "Forwarding from 127.0.0.1:${LOCAL_PORTS[$i]}" "/tmp/${SERVICES[$i]}-port-forward.log" 2>/dev/null; then
      disponibles=$((disponibles + 1))
    fi
  done
  [[ "$disponibles" -eq 3 ]] && break
  sleep 1
done

# Mostrar los accesos
for i in "${!SERVICES[@]}"; do
  service="${SERVICES[$i]}"
  port="${LOCAL_PORTS[$i]}"
  if grep -Fq "Forwarding from 127.0.0.1:${port}" "/tmp/${service}-port-forward.log" 2>/dev/null; then
    echo "$service: http://localhost:${port}"
  else
    echo "Error en $service. Revisa /tmp/${service}-port-forward.log"
  fi
done
