+++
title = "Установка DCGM Exporter в локальный Kubernetes-кластер с NVIDIA GPU"
date = 2026-04-23
description = "Как установить DCGM Exporter в локальный Kubernetes-кластер (k3s) с доступом к NVIDIA GPU внутри WSL2 и собирать детальные GPU-метрики для Prometheus."
[taxonomies]
tags = ["gpu", "kubernetes", "nvidia", "wsl2", "инфраструктура ИИ", "мониторинг"]
+++

В [предыдущей заметке](</all/wsl-nvidia-gpu/>) я рассказывал как развернуть локальный кластер Kubernetes с доступом к GPU внутри WSL2 окружения. Для того, чтобы собирать детальные метрики с видеокарты, _nvidia-smi_ не достаточно, т. к. GPU-Util показывает только активность в рамках короткого sampling-окна. Для анализа того, что происходит с GPU при обработке задач, нужен DCGM. [dcgm-exporter](<https://github.com/NVIDIA/dcgm-exporter>) — это утилита NVIDIA для сбора GPU-метрик через DCGM, которая отдает их через HTTP-метод /_metrics_ для Prometheus и похожих систем мониторинга.
<!-- more -->

При попытке установить _dcgm-exporter_ в k3s кластер Helm chart по умолчанию создает _ServiceMonitor_. Но если в кластере не установлен Prometheus оператор, процесс завершится с ошибкой:
    
    
    no matches for kind "ServiceMonitor" in version "monitoring.coreos.com/v1"
    ensure CRDs are installed first

Это ожидаемое поведение. В dcgm-exporter chart по умолчанию _serviceMonitor.enabled: true_ , а  _ServiceMonitor_ относится к CRD из экосистемы Prometheus Operator. В том же чарте _runtimeClassName_ — пустой.

Проверяем, что Kubernetes все еще видит GPU:
    
    
    kubectl get nodes -o json | jq '.items[].status.allocatable'

На моей системе результат такой:
    
    
    {
      "cpu": "20",
      "ephemeral-storage": "1027046117185",
      "hugepages-1Gi": "0",
      "hugepages-2Mi": "0",
      "memory": "16233644Ki",
      "nvidia.com/gpu": "1",
      "pods": "110"
    }

Далее добавляем репозиторий:
    
    
    helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts
    helm repo update

Отключаем создание _ServiceMonitor_ и указываем Nvidia runtime class:
    
    
    helm install dcgm-exporter gpu-helm-charts/dcgm-exporter \
      --set serviceMonitor.enabled=false \
      --set runtimeClassName=nvidia

Проверяем, что pod с экспортером поднялся:
    
    
    kubectl get pods -l app.kubernetes.io/name=dcgm-exporter -o wide
    kubectl logs -l app.kubernetes.io/name=dcgm-exporter --tail=50

Успешный запуск выглядит примерно так:
    
    
    Starting dcgm-exporter
    Attempting to initialize DCGM.
    Initialized DCGM Fields module.
    Attempting to initialize NVML library.
    NVML provider successfully initialized for Kubernetes MIG support
    DCGM successfully initialized!
    Successfully queried DCGM profiling metric groups
    HTTP server started - ready to serve metrics
    Listening on [::]:9400

Это означает, что:

  * DCGM инициализировался
  * NVML инициализировался
  * exporter увидел GPU
  * HTTP endpoint с метриками уже работает



Если chart создал сервис, его можно посмотреть так:
    
    
    kubectl get svc

Дальше пробрасываем порт:
    
    
    kubectl port-forward svc/dcgm-exporter 9400:9400

И проверяем:
    
    
    curl http://127.0.0.1:9400/metrics | head -50
    curl http://127.0.0.1:9400/health

Если все ок, /_health_ вернет успешный ответ, а /_metrics_ начнет отдавать метрики вида _DCGM_FI_*_.
