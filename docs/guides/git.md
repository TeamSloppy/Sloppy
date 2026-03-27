---
layout: doc
title: Git & Repositories
---

# Git & Repositories

Sloppy работает с Git в двух направлениях: **клонирование проектных репозиториев** (код, над которым работают агенты) и **синхронизация workspace** (сохранение конфигурации агентов в удалённый репозиторий). Обе возможности поддерживают приватные репозитории через Personal Access Token (PAT) или SSH.

## Приватные репозитории

По умолчанию Sloppy умеет клонировать только публичные репозитории. Чтобы работать с приватными, нужно подключить GitHub-аккаунт через Personal Access Token.

### Шаг 1. Создать токен на GitHub

1. Откройте [github.com/settings/tokens/new](https://github.com/settings/tokens/new?scopes=repo&description=Sloppy)
2. В поле **Note** введите `Sloppy`
3. В разделе **Select scopes** отметьте `repo` — это даёт доступ ко всем приватным репозиториям вашего аккаунта
4. Нажмите **Generate token** и скопируйте токен (он показывается только один раз)

### Шаг 2. Подключить токен в Dashboard

1. Откройте Dashboard → **Settings → Providers**
2. Прокрутите вниз до раздела **GitHub Access**
3. Вставьте токен в поле **Personal Access Token** и нажмите **Connect**

Sloppy проверит токен и отобразит имя вашего аккаунта. После этого клонирование приватных репозиториев будет работать автоматически.

### Альтернатива: переменная окружения

Если вы запускаете Sloppy через терминал или Docker, токен можно передать через переменную окружения — без сохранения в Dashboard:

```bash
GITHUB_TOKEN=ghp_ваш_токен swift run sloppy
```

Или в Docker Compose:

```yaml
environment:
  - GITHUB_TOKEN=ghp_ваш_токен
```

**Приоритет:** токен из Dashboard имеет приоритет над `GITHUB_TOKEN`.

### SSH-репозитории

Если вы используете URL в формате `git@github.com:org/repo.git`, Sloppy передаёт его в `git clone` как есть — авторизация происходит через SSH-ключи, настроенные в системе. Sloppy не управляет SSH-ключами самостоятельно.

Убедитесь, что SSH-агент запущен и ключ добавлен:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
ssh -T git@github.com   # проверка: должно вернуть имя аккаунта
```

---

## Клонирование репозитория в проект

При создании проекта вы можете указать URL репозитория. Sloppy клонирует его в директорию проекта — агенты получат доступ к коду и смогут работать с ним через инструменты файловой системы.

### Через Dashboard

1. Откройте Dashboard → **Projects → New Project**
2. Выберите источник **Clone from GitHub**
3. Вставьте URL репозитория (HTTPS или SSH)
4. Нажмите **Create**

Клонирование происходит в фоне. Репозиторий появится в директории проекта внутри workspace.

### Через API

```bash
curl -X POST http://localhost:25101/v1/projects \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ваш-токен" \
  -d '{
    "id": "my-project",
    "name": "My Project",
    "repoUrl": "https://github.com/org/private-repo"
  }'
```

### Где хранится код

Склонированный репозиторий находится здесь:

```
.sloppy/projects/{project-id}/
```

Путь настраивается через `workspace.basePath` и `workspace.name` в `sloppy.json`.

---

## Синхронизация workspace с Git

Git Sync сохраняет конфигурацию агентов (инструкции, настройки, политики инструментов) в удалённый репозиторий. Это позволяет:

- восстановить workspace после сброса
- переносить конфигурацию между серверами
- хранить историю изменений в агентах

::: warning
Git Sync синхронизирует только **конфигурацию** `.sloppy/` (AGENTS.md, config.json, tools.json и т.д.), но **не** данные памяти (SQLite), не сессии, не склонированный код проектов.
:::

### Настройка через Dashboard

1. Откройте **Settings → Git Sync**
2. Включите **Enable Sync**
3. Заполните поля:

| Поле | Описание |
| --- | --- |
| **Repository** | URL репозитория для синхронизации (HTTPS с токеном или SSH) |
| **Branch** | Ветка, по умолчанию `main` |
| **Auth Token** | GitHub PAT с правами `repo` (если репозиторий приватный) |
| **Schedule** | `manual`, `daily` или `weekdays` |
| **Sync Time** | Время синхронизации в формате `HH:MM` |
| **Conflict Strategy** | Что делать при конфликте: `remote_wins`, `local_wins` или `manual` |

4. Нажмите **Save Config**

### Настройка в `sloppy.json`

```json
{
  "gitSync": {
    "enabled": true,
    "repository": "https://github.com/org/sloppy-workspace",
    "branch": "main",
    "authToken": "ghp_ваш_токен",
    "schedule": {
      "frequency": "daily",
      "time": "18:00"
    },
    "conflictStrategy": "remote_wins"
  }
}
```

| Параметр | Тип | По умолчанию | Описание |
| --- | --- | --- | --- |
| `enabled` | bool | `false` | Включить синхронизацию |
| `repository` | string | `""` | URL репозитория |
| `branch` | string | `"main"` | Целевая ветка |
| `authToken` | string | `""` | GitHub PAT для приватного репозитория |
| `schedule.frequency` | string | `"daily"` | Расписание: `manual`, `daily`, `weekdays` |
| `schedule.time` | string | `"18:00"` | Время синхронизации (UTC) |
| `conflictStrategy` | string | `"remote_wins"` | Стратегия при конфликтах |

### Стратегии разрешения конфликтов

| Значение | Поведение |
| --- | --- |
| `remote_wins` | Удалённая версия перезаписывает локальную |
| `local_wins` | Локальная версия перезаписывает удалённую |
| `manual` | Синхронизация останавливается, конфликт нужно разрешить вручную |

---

## Частые вопросы

**Можно ли использовать несколько GitHub-аккаунтов?**

Sloppy хранит один токен для доступа к приватным репозиториям. Если нужен доступ к репозиториям из разных аккаунтов — используйте SSH с разными ключами (настраивается через `~/.ssh/config`) или создайте токен от организации, в которой есть доступ ко всем нужным репозиториям.

**Где хранится токен?**

Токен, введённый через Dashboard, сохраняется в файле `.sloppy/auth/github.json` внутри workspace. Файл доступен только на сервере, где запущен Sloppy.

**Что происходит, если токен истёк?**

Клонирование приватных репозиториев завершится ошибкой. В логах Sloppy появится `project.clone.failed` с кодом 128. Обновите токен через **Settings → Providers → GitHub Access**.

**Можно ли использовать Git Sync и GitHub Access с разными аккаунтами?**

Да. Git Sync использует токен из поля `authToken` в конфиге `gitSync`, а клонирование проектов — токен из **GitHub Access** (или `GITHUB_TOKEN`). Это независимые настройки.
