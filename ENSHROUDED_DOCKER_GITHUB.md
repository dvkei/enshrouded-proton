# Enshrouded Dedicated Server — Docker (GE-Proton) + GitHub Container Registry + Pterodactyl

Эта инструкция фиксирует рабочий вариант для Linux/Wings: **Debian 13 (trixie), GE-Proton 11-9, FreeType amd64/i386, Xvfb**. В проверке 18.10.2026 игровой сервер создал лог, подключился к Steam и перешёл в состояние `Run`. Сборка через `latest` может получить другую версию Proton; для воспроизводимости фиксируйте релиз и тестируйте новую сборку.

> Сборка и публикация выполняются в **своём репозитории**, а не напрямую в чужом `Ptero-Eggs/yolks`. Для исходного кода сохраняйте лицензию и авторство upstream.

## 1. Подготовка репозитория

На Linux-хосте с Docker и Git:

```bash
git clone https://github.com/Ptero-Eggs/yolks.git
cd yolks/steamcmd
```

Используем `steamcmd/` как контекст сборки, а `proton/Dockerfile` как Dockerfile — в этом проекте копируется `entrypoint.sh` из контекста.

## 2. Исправления Dockerfile

Из каталога `yolks/steamcmd`:

```bash
sed -i \
  -e 's/^FROM        debian:bookworm-slim/FROM        debian:trixie-slim/' \
  -e 's/ software-properties-common//' \
  -e 's/ tini file pipx$/ tini file pipx libvulkan1 libfreetype6 libfreetype6:i386/' \
  -e 's/egrep \.tar\.gz/grep -E x86_64\\.tar\\.gz/' \
  proton/Dockerfile
```

Убедитесь, что замены действительно сработали (upstream может измениться):

```bash
grep -nE '^FROM|libvulkan1|libfreetype|x86_64' proton/Dockerfile
```

Если `libfreetype6` не добавился, вручную добавьте `libvulkan1 libfreetype6 libfreetype6:i386` в строку второго `apt install`. Для выбранной ветки Debian может потребоваться проверить актуальные имена пакетов.

**Важно:** команда получения GE-Proton с GitHub `releases/latest` не фиксирует версию. В испытанной сборке была версия `GE-Proton11-9`. Для стабильного производства закрепите URL релиза, проверьте его checksum и не обновляйте автоматически без тестирования.

## 3. Локальная сборка и тестирование

```bash
docker build -f proton/Dockerfile -t enshrouded-proton:local .
docker run --rm --entrypoint /bin/bash enshrouded-proton:local -lc 'cat /usr/local/bin/version; dpkg-query -W libvulkan1 libfreetype6:amd64 libfreetype6:i386; command -v xvfb-run'
```

Для локального Pterodactyl можно дополнительно дать привычный тег:

```bash
docker tag enshrouded-proton:local local/steamcmd:proton
```

В настройках сервера Pterodactyl → Admin → Servers → Enshrouded → Startup → Docker Image используйте `~local/steamcmd:proton` **только если образ собран на той же Wings-ноде**. Тильда указывает Wings на локальный образ.

## 4. Сохранение изменений в собственном GitHub-репозитории

Самый простой путь — создать **fork** `Ptero-Eggs/yolks` на GitHub. Затем укажите свой fork как origin (замените `YOUR_GITHUB_USER`):

```bash
cd /root/yolks
git remote rename origin upstream
git remote add origin https://github.com/YOUR_GITHUB_USER/yolks.git
git checkout -b fix/enshrouded-proton
git add steamcmd/proton/Dockerfile
git commit -m "Fix Proton image for Enshrouded: trixie, Vulkan and FreeType"
git push -u origin fix/enshrouded-proton
```

Создайте Pull Request в **собственный** fork (или в upstream, если хотите предложить исправление). Для независимого репозитория адаптируйте путь и структуру проекта, сохранив `steamcmd/entrypoint.sh` и `steamcmd/proton/Dockerfile`.

## 5. Автоматическая публикация Docker-образа в GHCR

В своём fork создайте файл `.github/workflows/enshrouded-proton.yml`:

```yaml
name: Build Enshrouded Proton image
on:
  workflow_dispatch:
  push:
    branches: [main]
    paths:
      - 'steamcmd/proton/**'
      - 'steamcmd/entrypoint.sh'
      - '.github/workflows/enshrouded-proton.yml'

permissions:
  contents: read
  packages: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v6
        with:
          context: ./steamcmd
          file: ./steamcmd/proton/Dockerfile
          platforms: linux/amd64
          push: true
          tags: ghcr.io/${{ github.repository_owner }}/enshrouded-proton:latest
```

Запушьте workflow в `main` своего fork или вручную перенесите изменения туда. В GitHub перейдите в **Actions → Build Enshrouded Proton image → Run workflow**. Сборка GHCR должна завершиться успешно; проверить результат можно на странице **Packages**. Если образ приватный, Wings потребуется настроенная авторизация в GHCR; для простого использования сделайте пакет публичным в его настройках.

> Имя владельца GHCR в ссылке должно быть в нижнем регистре. Например, `ghcr.io/your_github_user/enshrouded-proton:latest`.

## 6. Использование опубликованного образа в Pterodactyl

На нужном сервере в **Admin → Servers → Enshrouded → Startup → Docker Image** укажите:

```text
ghcr.io/YOUR_GITHUB_USER/enshrouded-proton:latest
```

Для образа из GHCR **не** ставьте `~`: тильда нужна для локального Docker image. Желательно использовать версионированный тег или digest вместо `latest` после тестирования. Не забывайте, что после обновления образа требуется пересоздать контейнер сервера через штатный запуск Wings.

**Startup-команда (проверенный вариант запуска через Xvfb):**

```bash
mkdir -p ./logs; xvfb-run -a -s "-screen 0 1024x768x24" proton run ./enshrouded_server.exe & ENS_PID=$!; while kill -0 "$ENS_PID" 2>/dev/null && [ ! -f ./logs/enshrouded_server.log ]; do sleep 1; done; if [ -f ./logs/enshrouded_server.log ]; then tail -n +1 -F ./logs/enshrouded_server.log --pid="$ENS_PID" & fi; wait "$ENS_PID"
```

Если игровой лог остаётся от предыдущего запуска, старую версию стоит переименовать **до запуска** (не удаляйте логи без необходимости), иначе `tail` может читать старые строки. Для диагностики можно запускать напрямую через `xvfb-run` и читать `/home/container/logs/enshrouded_server.log`.

## 7. Контроль работоспособности

```bash
# Найти контейнер нужного сервера (при нескольких контейнерах используйте UUID сервера):
docker ps --format 'table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}'

# Вместо CONTAINER_ID укажите ID найденного контейнера:
docker exec CONTAINER_ID cat /usr/local/bin/version
docker exec CONTAINER_ID tail -n 80 /home/container/logs/enshrouded_server.log
docker exec CONTAINER_ID ss -lunp
```

Признаки успешного запуска в игровом логе:

```text
[online] Server connected to Steam successfully
[Session] 'HostOnline' (up)!
[game_server] Switching state from LoadEcsScene to Run
```

Проверьте отдельно доступность UDP-порта снаружи, правила firewall и достаточность RAM/CPU. `docker ps: Up` сам по себе не подтверждает готовность сервера.

## 8. Частые ошибки

- `Wine cannot find the FreeType font library` — проверьте `libfreetype6:amd64` и `libfreetype6:i386` внутри образа.
- `No such image: local/steamcmd:proton` — проверьте локальный тег, нужную Wings-ноду и `~` в конфигурации Pterodactyl.
- `fsync: up and running`, но нет игрового лога — используйте запуск через `xvfb-run`, затем изучите лог игры; само сообщение fsync не означает, что игра запустилась.
- `Failed to initialize DXVK`, `Xalia: No displays available` — возможны сообщения от вспомогательных графических компонентов; определяйте работоспособность по игровому логу и сети, а не только по этим строкам.
- `No SteamUtils011` — проверьте фактическую версию GE-Proton и актуальность образа; этот случай описан в upstream issue.

## Источники

- https://github.com/Ptero-Eggs/yolks/issues/27
- https://github.com/Ptero-Eggs/yolks/issues/27#issuecomment-6233934174
- https://github.com/Ptero-Eggs/yolks
