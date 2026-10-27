# Atribución de anuncios de Meta (Click-to-WhatsApp)

Guarda de qué anuncio viene cada lead que entra por WhatsApp Cloud API.

## Cómo funciona

1. Meta manda un objeto `referral` en el primer mensaje de un click en un anuncio. Chatwoot nativo lo descarta.
2. `Arroyo::Ads::ReferralRecorderService` (hook `# ARROYO:` en `Whatsapp::IncomingMessageBaseService#process_messages`) lo copia a `additional_attributes` de la conversación: `ad_source`, `ad_id`, `ad_source_type`, `ad_source_url`, `ad_headline`, `ad_body`, `ad_media_type`, `ad_ctwa_clid`. No guarda las URLs de media: Meta las vence.
3. Si la cuenta tiene token, `Arroyo::Ads::CampaignResolverJob` consulta la Marketing API (`GET /{ad_id}?fields=name,adset{id,name},campaign{id,name}`) y agrega `ad_name`, `ad_adset_*` y `ad_campaign_*`. Cachea por anuncio un día y reintenta 3 veces.
4. La ficha de la conversación muestra el bloque "Anuncio de Meta" (`AdSourceInfo.vue`).

Meta manda solo el ID del anuncio: sin token queda el ID, con token también los nombres.

## Activarlo

1. Token: usuario del sistema del portfolio con acceso de solo lectura a la cuenta publicitaria y token con permiso `ads_read` (vencimiento "Nunca").
2. Configuración → Arroyo → Atribución de anuncios: prender la función y pegar el token. El campo vacío conserva el token guardado.
3. El token va cifrado en `arroyo_settings.meta_ads_token` **solo si** el servidor tiene `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` y `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`. Sin esas variables queda en texto plano. La API nunca lo devuelve (solo `token_set`).

## Límites

- Solo WhatsApp Cloud API. Instagram no está cubierto.
- Solo se registra en mensajes entrantes con `referral`; las conversaciones anteriores a activar la función no se completan.
- Si el token es inválido el job lo registra en el log y no reintenta más de 3 veces; la conversación conserva el `ad_id`.
- Migración: agrega la columna `meta_ads_token` a `arroyo_settings` (no toca tablas nativas).
