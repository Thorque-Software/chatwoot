<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import SectionCard from './SectionCard.vue';
import SwitchField from './SwitchField.vue';
import { MAX_WINDOW_NUDGE_LENGTH, NUDGE_VARIABLES } from '../constants';

// Una sola sección para todo el embudo del panel: abandonadas, etiquetas, números y aviso de ventana.
const props = defineProps({
  config: { type: Object, required: true },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['save']);

const { t } = useI18n();
const inboxes = useMapGetter('inboxes/getInboxes');
const form = ref(null);
const newLabel = ref('');
const showErrors = ref(false);

const CLOCK = /^([01]\d|2[0-3]):[0-5]\d$/;
const splitList = value =>
  value
    .split(',')
    .map(item => item.trim())
    .filter(Boolean);

const selectedInboxes = computed(() =>
  form.value.inboxes.filter(item => item.selected)
);
const errors = computed(() => {
  const nudge = form.value.window_nudge;
  return {
    abandonHours: !(
      Number.isInteger(Number(form.value.abandon_hours)) &&
      Number(form.value.abandon_hours) >= 1 &&
      Number(form.value.abandon_hours) <= 720
    ),
    lostLabel: !form.value.lost_label.trim(),
    repurchaseLabel: !form.value.repurchase_label.trim(),
    inboxName: selectedInboxes.value.some(item => !item.name.trim()),
    nudgeText: !nudge.text.trim(),
    nudgeTimes:
      !CLOCK.test(nudge.morning_time) ||
      !CLOCK.test(nudge.evening_time) ||
      nudge.morning_time >= nudge.evening_time,
  };
});
const hasErrors = computed(() => Object.values(errors.value).some(Boolean));

const addLabel = () => {
  const label = newLabel.value.trim();
  if (!label || form.value.info_labels.some(item => item.label === label))
    return;
  form.value.info_labels.push({ label, enabled: true });
  newLabel.value = '';
};
const removeLabel = index => form.value.info_labels.splice(index, 1);

const buildInboxRows = saved =>
  inboxes.value.map(inbox => {
    const match = saved.find(item => item.id === inbox.id);
    return {
      id: inbox.id,
      selected: Boolean(match),
      name: match ? match.name : inbox.name,
      original: inbox.name,
    };
  });

const save = () => {
  showErrors.value = hasErrors.value;
  if (showErrors.value) return;
  const nudge = form.value.window_nudge;
  emit('save', {
    funnel_board: {
      enabled: form.value.enabled,
      abandon_hours: Number(form.value.abandon_hours),
      lost_label: form.value.lost_label.trim(),
      repurchase_label: form.value.repurchase_label.trim(),
      info_labels: form.value.info_labels.map(({ label, enabled }) => ({
        label,
        enabled,
      })),
      inboxes: selectedInboxes.value.map(({ id, name }) => ({
        id,
        name: name.trim(),
      })),
      window_nudge: {
        enabled: nudge.enabled,
        text: nudge.text.trim(),
        morning_time: nudge.morning_time,
        evening_time: nudge.evening_time,
        skip_sundays: nudge.skip_sundays,
        margin_minutes: Number(nudge.margin_minutes),
        skip_labels: splitList(nudge.skip_labels),
      },
    },
  });
};

const load = config => {
  form.value = {
    ...config,
    info_labels: (config.info_labels || []).map(item => ({ ...item })),
    inboxes: buildInboxRows(config.inboxes || []),
    window_nudge: {
      ...config.window_nudge,
      skip_labels: (config.window_nudge?.skip_labels || []).join(', '),
    },
  };
  showErrors.value = false;
};

watch(() => props.config, load, { immediate: true });
// Las bandejas llegan del store después de montar: se completan sin perder lo guardado.
watch(inboxes, () => {
  const saved = form.value.inboxes
    .filter(item => item.selected)
    .map(({ id, name }) => ({ id, name }));
  form.value.inboxes = buildInboxRows(
    saved.length ? saved : props.config.inboxes || []
  );
});
</script>

<template>
  <SectionCard
    v-model:enabled="form.enabled"
    :title="t('ARROYO.SETTINGS.FUNNEL_BOARD.TITLE')"
    :description="t('ARROYO.SETTINGS.FUNNEL_BOARD.DESCRIPTION')"
    :is-saving="isSaving"
    @save="save"
  >
    <div class="grid gap-4 md:grid-cols-3">
      <Input
        v-model="form.abandon_hours"
        type="number"
        min="1"
        max="720"
        :label="t('ARROYO.SETTINGS.FUNNEL_BOARD.ABANDON_HOURS.LABEL')"
        :message="t('ARROYO.SETTINGS.FUNNEL_BOARD.ABANDON_HOURS.HELP')"
        :message-type="showErrors && errors.abandonHours ? 'error' : 'info'"
        data-testid="abandon-hours"
      />
      <Input
        v-model="form.lost_label"
        :label="t('ARROYO.SETTINGS.FUNNEL_BOARD.LOST_LABEL.LABEL')"
        :message="t('ARROYO.SETTINGS.FUNNEL_BOARD.LOST_LABEL.HELP')"
        :message-type="showErrors && errors.lostLabel ? 'error' : 'info'"
        data-testid="lost-label"
      />
      <Input
        v-model="form.repurchase_label"
        :label="t('ARROYO.SETTINGS.FUNNEL_BOARD.REPURCHASE_LABEL.LABEL')"
        :message="t('ARROYO.SETTINGS.FUNNEL_BOARD.REPURCHASE_LABEL.HELP')"
        :message-type="showErrors && errors.repurchaseLabel ? 'error' : 'info'"
        data-testid="repurchase-label"
      />
    </div>

    <fieldset class="flex flex-col gap-3 border-0 p-0 m-0">
      <legend class="mb-1 text-body-main text-n-slate-12">
        {{ t('ARROYO.SETTINGS.FUNNEL_BOARD.INFO_LABELS.LABEL') }}
      </legend>
      <p class="mb-0 text-label-small text-n-slate-11">
        {{ t('ARROYO.SETTINGS.FUNNEL_BOARD.INFO_LABELS.HELP') }}
      </p>
      <div class="flex flex-wrap gap-2">
        <span
          v-for="(item, index) in form.info_labels"
          :key="item.label"
          class="flex items-center gap-2 rounded-lg border border-n-weak bg-n-solid-1 py-1 ps-3 pe-1 text-body-main text-n-slate-12"
          :data-testid="`info-label-${item.label}`"
        >
          {{ item.label }}
          <Switch v-model="item.enabled" />
          <Button
            icon="i-lucide-x"
            slate
            ghost
            xs
            :aria-label="
              t('ARROYO.SETTINGS.FUNNEL_BOARD.INFO_LABELS.REMOVE', {
                label: item.label,
              })
            "
            @click="removeLabel(index)"
          />
        </span>
      </div>
      <div class="flex items-end gap-2">
        <Input
          v-model="newLabel"
          class="flex-1"
          :label="t('ARROYO.SETTINGS.FUNNEL_BOARD.INFO_LABELS.NEW')"
          data-testid="new-info-label"
          @enter="addLabel"
        />
        <Button
          icon="i-lucide-plus"
          slate
          faded
          sm
          :label="t('ARROYO.SETTINGS.FUNNEL_BOARD.INFO_LABELS.ADD')"
          data-testid="add-info-label"
          @click="addLabel"
        />
      </div>
    </fieldset>

    <fieldset class="flex flex-col gap-3 border-0 p-0 m-0">
      <legend class="mb-1 text-body-main text-n-slate-12">
        {{ t('ARROYO.SETTINGS.FUNNEL_BOARD.INBOXES.LABEL') }}
      </legend>
      <p class="mb-0 text-label-small text-n-slate-11">
        {{ t('ARROYO.SETTINGS.FUNNEL_BOARD.INBOXES.HELP') }}
      </p>
      <div
        v-for="item in form.inboxes"
        :key="item.id"
        class="grid items-center gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-3 md:grid-cols-[auto_1fr_1fr]"
        :data-testid="`board-inbox-${item.id}`"
      >
        <Switch v-model="item.selected" />
        <span class="text-body-main text-n-slate-11">{{ item.original }}</span>
        <Input
          v-model="item.name"
          :disabled="!item.selected"
          :placeholder="t('ARROYO.SETTINGS.FUNNEL_BOARD.INBOXES.NAME')"
          :message-type="
            showErrors && item.selected && !item.name.trim() ? 'error' : 'info'
          "
        />
      </div>
    </fieldset>

    <fieldset
      class="flex flex-col gap-4 rounded-xl border border-n-weak p-4 m-0"
    >
      <legend class="px-1 text-body-main text-n-slate-12">
        {{ t('ARROYO.SETTINGS.FUNNEL_BOARD.WINDOW_NUDGE.TITLE') }}
      </legend>
      <p class="mb-0 text-label-small text-n-slate-11">
        {{ t('ARROYO.SETTINGS.FUNNEL_BOARD.WINDOW_NUDGE.HELP') }}
      </p>
      <SwitchField
        v-model="form.window_nudge.enabled"
        :label="t('ARROYO.SETTINGS.FUNNEL_BOARD.WINDOW_NUDGE.ENABLED')"
        data-testid="window-nudge-enabled"
      />
      <TextArea
        v-model="form.window_nudge.text"
        :max-length="MAX_WINDOW_NUDGE_LENGTH"
        :label="t('ARROYO.SETTINGS.FUNNEL_BOARD.WINDOW_NUDGE.TEXT')"
        show-character-count
        auto-height
        class="w-full"
        data-testid="window-nudge-text"
      />
      <p
        class="mb-0 -mt-2 flex flex-wrap items-center gap-1.5 text-label-small text-n-slate-11"
      >
        {{ t('ARROYO.SETTINGS.FUNNEL_BOARD.WINDOW_NUDGE.VARIABLES') }}
        <code
          v-for="variable in NUDGE_VARIABLES"
          :key="variable"
          class="rounded bg-n-alpha-2 px-1.5 py-0.5"
          >{{ variable }}</code
        >
      </p>
      <div class="grid gap-4 md:grid-cols-3">
        <Input
          v-model="form.window_nudge.morning_time"
          type="time"
          :label="t('ARROYO.SETTINGS.FUNNEL_BOARD.WINDOW_NUDGE.MORNING_TIME')"
          :message-type="showErrors && errors.nudgeTimes ? 'error' : 'info'"
          data-testid="window-nudge-morning"
        />
        <Input
          v-model="form.window_nudge.evening_time"
          type="time"
          :label="t('ARROYO.SETTINGS.FUNNEL_BOARD.WINDOW_NUDGE.EVENING_TIME')"
          :message-type="showErrors && errors.nudgeTimes ? 'error' : 'info'"
          data-testid="window-nudge-evening"
        />
        <Input
          v-model="form.window_nudge.margin_minutes"
          type="number"
          min="0"
          max="240"
          :label="t('ARROYO.SETTINGS.FUNNEL_BOARD.WINDOW_NUDGE.MARGIN')"
        />
      </div>
      <SwitchField
        v-model="form.window_nudge.skip_sundays"
        :label="t('ARROYO.SETTINGS.FUNNEL_BOARD.WINDOW_NUDGE.SKIP_SUNDAYS')"
      />
      <Input
        v-model="form.window_nudge.skip_labels"
        :label="t('ARROYO.SETTINGS.FUNNEL_BOARD.WINDOW_NUDGE.SKIP_LABELS')"
        :message="t('ARROYO.SETTINGS.FUNNEL_BOARD.WINDOW_NUDGE.SKIP_LABELS_HELP')"
        data-testid="window-nudge-skip-labels"
      />
    </fieldset>

    <p
      v-if="showErrors && hasErrors"
      role="alert"
      class="mb-0 text-body-main text-n-ruby-11"
      data-testid="funnel-board-errors"
    >
      {{ t('ARROYO.SETTINGS.FUNNEL_BOARD.INVALID') }}
    </p>
  </SectionCard>
</template>
