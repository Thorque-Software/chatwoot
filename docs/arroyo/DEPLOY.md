# Deploy de Chatwoot Arroyo con los datos de producción

Guía para pasar de la instalación actual (imagen oficial `chatwoot/chatwoot:v4.14.2`) a la imagen construida desde este fork (branch `arroyo/main`), conservando todos los datos.

Contexto:

- El fork **es la misma versión de Chatwoot que prod (4.14.2)** con el código Arroyo encima. No hay upgrade de Chatwoot: las únicas migraciones nuevas son dos tablas `arroyo_*` (`arroyo_settings`, `arroyo_assignment_events`). No modifican tablas existentes.
- Todas las funciones Arroyo arrancan **apagadas**. Recién después del deploy se activan de a una, desde Configuración → Arroyo.
- La imagen incluye `enterprise/`, así que el código EE queda activo (igual que en la imagen oficial sin `-ce`).

Lo que hay que llevar del entorno viejo al nuevo:

| Qué | Dónde está | Obligatorio |
|---|---|---|
| Base de datos Postgres | contenedor `postgres` (volumen `postgres_data`) | sí |
| Archivos adjuntos | volumen `storage_data` (`/app/storage`) si `ACTIVE_STORAGE_SERVICE=local`; si es S3/GCS, no hay nada que copiar | sí, si es local |
| Archivo `.env` | junto al `docker-compose` | sí, **completo** |
| Redis | volumen `redis_data` | recomendado (jobs programados de Sidekiq) |

> **El `.env` tiene que ser el mismo.** `SECRET_KEY_BASE` y, si existen, `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` y `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` tienen que ser idénticos. Si cambian, los datos encriptados quedan ilegibles (tokens de canales, por ejemplo) y se invalidan todas las sesiones.

---

## 1. Construir la imagen

En una máquina con Docker y al menos 6 GB de RAM (la compilación del frontend usa hasta 4 GB):

```bash
git clone git@github.com:Thorque-Software/chatwoot.git chatwoot-arroyo
cd chatwoot-arroyo
git checkout arroyo/main
SHA=$(git rev-parse --short HEAD)

docker build -f docker/Dockerfile -t <registro>/chatwoot-arroyo:4.14.2-arroyo-$SHA .
docker push <registro>/chatwoot-arroyo:4.14.2-arroyo-$SHA
```

- El build necesita la carpeta `.git` (el Dockerfile guarda el commit en `/app/.git_sha`), así que se construye desde un clon, no desde un zip.
- Usar siempre un **tag fijo** con el commit, nunca `latest`, para poder volver atrás.
- Si no hay registro privado, se puede construir directamente en el servidor nuevo y saltear el `push`.

## 2. Ensayo en staging (recomendado antes de prod)

Hacer los pasos 3 a 6 en un entorno de staging con un dump de prod, **sin** cambiar el DNS. Cuidados para que staging no hable con clientes reales:

- Usar otro `FRONTEND_URL` (ej. `https://staging-chatarroyo.thorque.com.ar`).
- **No levantar `sidekiq`** salvo para probar algo puntual. Sidekiq envía mensajes, campañas, encuestas CSAT, y lee las casillas IMAP de los inboxes de email.
- Los webhooks de Meta siguen apuntando a prod, así que staging no recibe mensajes de WhatsApp/Instagram. Para probar envíos reales hay que usar el número de prueba de WhatsApp Cloud (ver `PLAN.md`, Fase 6).

## 3. Sacar los datos del entorno viejo

Elegir un horario de poco tráfico. El corte dura lo que tarden el dump y el restore (en general minutos).

En el servidor viejo, dentro de la carpeta del `docker-compose`:

```bash
# 3.1 Frenar la app para que no entren datos nuevos (Postgres y Redis siguen arriba)
docker compose stop rails sidekiq

# 3.2 Dump de la base (formato custom, comprimido)
docker compose exec -T postgres pg_dump -U postgres -d chatwoot -Fc > chatwoot_$(date +%F_%H%M).dump

# 3.3 Versión de Postgres de origen (el destino tiene que ser igual o mayor)
docker compose exec -T postgres psql -U postgres -d chatwoot -c 'select version();'

# 3.4 Adjuntos (solo si ACTIVE_STORAGE_SERVICE=local)
docker volume ls | grep storage_data        # nombre real del volumen, ej. chatwoot_storage_data
docker run --rm -v <volumen_storage>:/data -v "$PWD":/backup alpine tar czf /backup/storage.tgz -C /data .

# 3.5 Redis (recomendado): bajar Redis para que vuelque todo a disco y copiar el volumen
docker compose stop redis
docker volume ls | grep redis_data
docker run --rm -v <volumen_redis>:/data -v "$PWD":/backup alpine tar czf /backup/redis.tgz -C /data .

# 3.6 Copiar el .env
cp .env env.backup
```

Llevar `chatwoot_*.dump`, `storage.tgz`, `redis.tgz` y `env.backup` al servidor nuevo (con `scp` o `rsync`).

> Mientras la app está frenada, Meta reintenta los webhooks de WhatsApp que no pudo entregar, así que los mensajes entrantes no se pierden si el corte es corto. **No borrar ni modificar el entorno viejo**: es el plan de vuelta atrás.

## 4. Levantar el entorno nuevo con los datos

En el servidor nuevo:

```bash
mkdir chatwoot-arroyo && cd chatwoot-arroyo
cp /ruta/env.backup .env
```

Revisar en `.env`:

- `FRONTEND_URL`: el dominio con el que va a quedar (si se mantiene `https://chatarroyo.thorque.com.ar`, no cambia).
- `POSTGRES_HOST`, `POSTGRES_PASSWORD`, `REDIS_URL`, `REDIS_PASSWORD`: que apunten a los servicios del compose nuevo.

Crear `docker-compose.yaml` a partir de `docker-compose.production.yaml` del repo, cambiando solo la imagen de `base`:

```yaml
services:
  base: &base
    image: <registro>/chatwoot-arroyo:4.14.2-arroyo-<sha>
    env_file: .env
    volumes:
      - storage_data:/app/storage
  # rails, sidekiq, postgres (pgvector/pgvector:pg16) y redis: igual que docker-compose.production.yaml
```

Postgres tiene que ser la imagen `pgvector/pgvector` (Chatwoot usa la extensión `vector`), con versión mayor igual o superior a la de origen (paso 3.3).

```bash
# 4.1 Levantar solo Postgres y restaurar
docker compose up -d postgres
docker compose exec -T postgres pg_restore -U postgres -d chatwoot --no-owner --clean --if-exists < /ruta/chatwoot_XXXX.dump

# 4.2 Restaurar adjuntos (si eran locales). El volumen se crea con el primer "up"; si no existe: docker volume create <volumen>
docker compose create rails
docker run --rm -v <volumen_storage_nuevo>:/data -v /ruta:/backup alpine sh -c 'cd /data && tar xzf /backup/storage.tgz'

# 4.3 Restaurar Redis (opcional) antes de levantarlo
docker run --rm -v <volumen_redis_nuevo>:/data -v /ruta:/backup alpine sh -c 'cd /data && tar xzf /backup/redis.tgz'
docker compose up -d redis

# 4.4 Correr migraciones (crea solo las dos tablas arroyo_*)
docker compose run --rm rails bundle exec rails db:chatwoot_prepare

# 4.5 Verificar que las tablas Arroyo existen
docker compose run --rm rails bundle exec rails runner \
  'puts %w[arroyo_settings arroyo_assignment_events].map { |t| [t, ActiveRecord::Base.connection.table_exists?(t)] }.inspect'

# 4.6 Levantar todo
docker compose up -d
```

Los nombres reales de los volúmenes salen de `docker volume ls`. Docker les antepone el nombre de la carpeta del proyecto, ej. `chatwoot-arroyo_storage_data`.

## 5. Cambiar el tráfico

- Apuntar `chatarroyo.thorque.com.ar` (DNS o reverse proxy) al servidor nuevo, puerto 3000.
- El proxy tiene que pasar WebSockets en `/cable` (`Upgrade` / `Connection` headers); si no, el dashboard no se actualiza en vivo.
- **Si el dominio no cambia**, no hay que tocar nada en Meta: los webhooks de WhatsApp e Instagram siguen apuntando al mismo URL.
- Si el dominio cambia: actualizar `FRONTEND_URL` y las URLs de callback en la app de Meta (WhatsApp e Instagram).

## 6. Verificación después del deploy

1. `curl https://chatarroyo.thorque.com.ar/api` responde con `"version":"4.14.2"`, `queue_services: ok` y `data_services: ok`.
2. Login con un usuario existente, sin tener que volver a crear la cuenta (confirma que la base y `SECRET_KEY_BASE` son los correctos).
3. Abrir conversaciones viejas: se ven los mensajes y **cargan las imágenes y adjuntos** (confirma el storage).
4. Mandar un mensaje de WhatsApp al número del negocio y verificar que entra, que el bot de n8n responde como antes y que una respuesta de un vendedor llega al teléfono.
5. Sidekiq procesando: Super Admin → Sidekiq (`/monitoring/sidekiq`), sin colas trabadas.
6. Configuración → Arroyo aparece en el menú de un administrador, con todo apagado.

Si todo está bien, activar las funciones de a una desde Configuración → Arroyo (primero el panel de vendedores).

## 7. Volver atrás

Mientras el entorno viejo siga intacto:

```bash
# en el servidor nuevo
docker compose stop rails sidekiq
# en el servidor viejo
docker compose up -d
```

Después, volver el DNS o proxy al servidor viejo. Ojo: lo que haya entrado al entorno nuevo después del cambio **no** vuelve solo al viejo. Por eso conviene decidir rápido (las primeras horas) y, si hay que volver, hacerlo antes de que se acumulen conversaciones nuevas.

Las tablas `arroyo_*` no molestan a la imagen oficial, así que también se puede volver atrás en el mismo servidor: cambiar la imagen a `chatwoot/chatwoot:v4.14.2` y `docker compose up -d`.

## Deploys siguientes (mismo servidor, código nuevo del fork)

Para cada fase nueva:

1. Construir la imagen con el tag del nuevo commit (paso 1).
2. Backup de la base: `docker compose exec -T postgres pg_dump -U postgres -d chatwoot -Fc > backup_$(date +%F).dump`.
3. Cambiar el tag de la imagen en el compose.
4. `docker compose run --rm rails bundle exec rails db:chatwoot_prepare`.
5. `docker compose up -d`.
