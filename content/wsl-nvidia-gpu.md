+++
title = "Kubernetes с доступом к GPU внутри WSL2 на ноутбуке с RTX"
date = 2026-04-22
[taxonomies]
tags = []
+++

На днях мне понадобилась локальная среда c Kubernetes для запуска GPU задач и тестирования сервисов с ИИ. Мой рабочий компьютер — это ноутбук Lenovo Legion следующей конфигурации:

  * Процессор 13th Gen Intel(R) Core(TM) i7-13650HX (2.60 GHz)
  * Оперативная память 32 GB
  * Видеокарта NVIDIA GeForce RTX 5070 Laptop GPU
  * Диск 1 TB SSD



Каждый раз арендовать облако и временно развертывать K8s-окружение, чтобы экономить на стоимости — не очень удобно. Поэтому я решил попробовать сконфигурировать локальную среду. Оказалось, что Kubernetes с доступом к GPU внутри WSL2 — это реально. Но есть несколько неочевидных нюансов, которые ломают рантайм.

### TL;DR

Итоговый стек:

  * Windows 11 + NVIDIA driver (с поддержкой WSL)
  * [Podman](<https://podman.io/>)
  * WSL2 (Ubuntu 24.04)
  * K3s (containerd)
  * NVIDIA Container Toolkit
  * NVIDIA device plugin
  * фикс: _runtimeClassName: nvidia_ для device plugin



### Что хотелось получить

По сути — мини-кластер на ноутбуке, который работает по следующей схеме:

Pod → Kubernetes → containerd → NVIDIA runtime → WSL GPU → Windows driver → RTX GPU

С возможностью делать:

  * локальный инференс
  * эксперименты с AI-инфраструктурой и GPU



### Шаг 1: Проверка GPU в WSL

Если после установки WSL2 у вас работает [Nvidia System Management](<https://docs.nvidia.com/deploy/nvidia-smi/index.html>):
    
    
    nvidia-smi

— двигаемся дальше.

### Шаг 2: Linux-драйверы

WSL — особенная штука. Драйвер для GPU живет в Windows, Linux просто проксирует доступ через /_usr/lib/wsl_

Если nvidia-smi не находится:
    
    
    echo 'export PATH=$PATH:/usr/lib/wsl/lib' >> ~/.bashrc
    source ~/.bashrc

Чего не стоит делать:
    
    
    apt install nvidia-utils-*

Такая установка системных пакетов внутри Linux почти гарантированно все сломает.

### Шаг 3: Проверка GPU в контейнерах

Перед установкой Kubernetes важно убедиться, что GPU работает в контейнерах.
    
    
    sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
    podman run --rm --device=nvidia.com/gpu=all ubuntu nvidia-smi

Если последняя команда выполняется успешно, то runtime настроен правильно.

### Шаг 4: Установка K3s
    
    
    curl -sfL https://get.k3s.io | sh -

Настраиваем kubeconfig:
    
    
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $USER:$USER ~/.kube/config
    export KUBECONFIG=~/.kube/config

Проверяем доступна ли наша единственная Kubernetes нода:
    
    
    kubectl get nodes

### Шаг 5: Подключение NVIDIA runtime
    
    
    sudo nvidia-ctk runtime configure --runtime=containerd
    sudo systemctl restart k3s

После перезапуска K3s убеждаемся, что поддержка GPU есть в конфиге:
    
    
    sudo grep nvidia /var/lib/rancher/k3s/agent/etc/containerd/config.toml

### Шаг 6: Установка device plugin
    
    
    kubectl apply -f \
    https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.1/deployments/static/nvidia-device-plugin.yml

### NVIDIA runtime и device plugin

После выполнения шага 6 я столкнулся со следующей ситуацией вокруг device plugin — он запускается и не падает, но не видит GPU. В логах можно увидеть:
    
    
    No devices found. Waiting indefinitely.
    Incompatible strategy detected auto

Причина такого поведения кроется в том, что device plugin запускается под обычным runtime (runc), а не под NVIDIA runtime. Т. е.:

  * внутри pod’а нет CUDA / NVML
  * GPU не может быть обнаружен
  * _nvidia.com/gpu_ не регистрируется



Нужно заставить сам device plugin использовать NVIDIA runtime:
    
    
    kubectl patch daemonset nvidia-device-plugin-daemonset \
      -n kube-system \
      --type='merge' \
      -p '{"spec":{"template":{"spec":{"runtimeClassName":"nvidia"}}}}'

Перезапускаем pod:
    
    
    kubectl delete pod -n kube-system -l name=nvidia-device-plugin-ds

и проверяем доступные GPU:
    
    
    kubectl get node -o jsonpath='{.status.capacity.nvidia\.com/gpu}'

Команда должна вернуть _1_.

### Финальная проверка

Для тестирования работы GPU внутри WSL2 можно запустить следующий pod:
    
    
    cat <<'EOF' | kubectl apply -f -
    apiVersion: v1
    kind: Pod
    metadata:
      name: cuda-smoke-test
    spec:
      restartPolicy: Never
      runtimeClassName: nvidia
      containers:
      - name: cuda
        image: nvcr.io/nvidia/k8s/cuda-sample:nbody
        args: ["nbody", "-gpu", "-benchmark"]
        resources:
          limits:
            nvidia.com/gpu: 1
    EOF

и проверить его состояние и логи:
    
    
    kubectl get pod cuda-smoke-test -w
    kubectl logs cuda-smoke-test

### Что в итоге получилось

  * локальный Kubernetes на ноутбуке с Nvidia RTX 5070 (8GB vRAM)
  * с возможность GPU scheduling
  * тестирования задач с CUDA и LLM



Такое окружение хорошо подходит для локального инференса LLM, экспериментов и обучения. Но его не стоит использовать для бенчмарков и более серьезных задач.
