// Pure functions embedded verbatim in n8n Code nodes by post_sale-build.cjs.
function zonedParts(value, timezone) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(new Date(value));
  return Object.fromEntries(
    parts
      .filter(part => part.type !== 'literal')
      .map(part => [part.type, Number(part.value)])
  );
}

function localInstant(day, hour, timezone) {
  const wanted = Date.UTC(
    day.getUTCFullYear(),
    day.getUTCMonth(),
    day.getUTCDate(),
    hour
  );
  let instant = wanted;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const parts = zonedParts(instant, timezone);
    const actual = Date.UTC(
      parts.year,
      parts.month - 1,
      parts.day,
      parts.hour,
      parts.minute,
      parts.second
    );
    instant += wanted - actual;
  }
  return new Date(instant).toISOString();
}

function planPurchase(purchase, config) {
  const local = zonedParts(purchase.purchased_at, config.timezone);
  const stages = Object.fromEntries(
    ['d1', 'd7', 'd30'].map(stage => {
      const day = new Date(
        Date.UTC(
          local.year,
          local.month - 1,
          local.day + config.stages[stage].days
        )
      );
      if (config.skip_sundays && day.getUTCDay() === 0)
        day.setUTCDate(day.getUTCDate() + 1);
      return [
        stage,
        localInstant(day, config.send_hour_local, config.timezone),
      ];
    })
  );
  return { revision: purchase.revision, stages };
}

function purchaseItems(pages) {
  const seen = new Set();
  return pages.flatMap(page => {
    if (!page.config.enabled) return [];
    return page.purchases
      .filter(purchase => {
        if (seen.has(purchase.reference)) return false;
        seen.add(purchase.reference);
        return true;
      })
      .map(purchase => ({ purchase, config: page.config }));
  });
}

function activeConversationIds(pages) {
  return [
    ...new Set(
      purchaseItems(pages).map(item => String(item.purchase.conversation_id))
    ),
  ];
}

function dueMessages(purchase, config, now, executionId) {
  if (!config.enabled || purchase.revision !== purchase.planned_revision)
    return [];
  const ageLimit = config.delivery_timeout_hours * 60 * 60 * 1000;
  return purchase.follow_ups
    .filter(followUp => {
      const age =
        new Date(now).getTime() - new Date(followUp.scheduled_at).getTime();
      return (
        followUp.status === 'scheduled' &&
        !followUp.message_id &&
        !followUp.attempted_at &&
        age >= 0 &&
        age < ageLimit
      );
    })
    .map(followUp => {
      const body = { revision: purchase.revision };
      if (executionId) body.execution_id = executionId;
      return {
        id: followUp.id,
        reference: purchase.reference,
        conversation_id: purchase.conversation_id,
        stage: followUp.stage,
        body,
      };
    });
}

module.exports = {
  planPurchase,
  purchaseItems,
  dueMessages,
  activeConversationIds,
};
