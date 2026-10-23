<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SectionCard from './SectionCard.vue';

const props = defineProps({
  config: { type: Object, required: true },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['save']);

const { t } = useI18n();
const form = ref(null);
const showErrors = ref(false);

const hasBlankAlias = computed(() =>
  form.value.aliases.some(({ name, alias }) => !name.trim() || !alias.trim())
);

const addAlias = () => {
  form.value.aliases.push({ name: '', alias: '' });
};

const removeAlias = index => {
  form.value.aliases.splice(index, 1);
};

const save = () => {
  showErrors.value = hasBlankAlias.value;
  if (showErrors.value) return;
  emit('save', {
    follow_up: {
      enabled: form.value.enabled,
      aliases: form.value.aliases.map(({ name, alias }) => ({
        name: name.trim(),
        alias: alias.trim(),
      })),
    },
  });
};

watch(
  () => props.config,
  config => {
    form.value = {
      enabled: false,
      ...config,
      aliases: (config.aliases || []).map(item => ({ ...item })),
    };
    showErrors.value = false;
  },
  { immediate: true }
);
</script>

<template>
  <SectionCard
    v-model:enabled="form.enabled"
    :title="t('ARROYO.SETTINGS.FOLLOW_UP.TITLE')"
    :description="t('ARROYO.SETTINGS.FOLLOW_UP.DESCRIPTION')"
    :is-saving="isSaving"
    @save="save"
  >
    <div class="flex flex-col gap-3">
      <div class="flex flex-col gap-1">
        <span class="text-body-main text-n-slate-12">
          {{ t('ARROYO.SETTINGS.FOLLOW_UP.ALIASES.LABEL') }}
        </span>
        <p class="mb-0 text-label-small text-n-slate-11">
          {{ t('ARROYO.SETTINGS.FOLLOW_UP.ALIASES.HELP') }}
        </p>
      </div>
      <p
        v-if="!form.aliases.length"
        class="mb-0 text-body-main text-n-slate-11"
      >
        {{ t('ARROYO.SETTINGS.FOLLOW_UP.ALIASES.EMPTY') }}
      </p>
      <div
        v-for="(item, index) in form.aliases"
        :key="index"
        class="grid items-end gap-3 md:grid-cols-[1fr_1fr_auto]"
        :data-testid="`alias-${index}`"
      >
        <Input
          v-model="item.name"
          :label="t('ARROYO.SETTINGS.FOLLOW_UP.ALIASES.NAME')"
          :message-type="showErrors && !item.name.trim() ? 'error' : 'info'"
        />
        <Input
          v-model="item.alias"
          :label="t('ARROYO.SETTINGS.FOLLOW_UP.ALIASES.ALIAS')"
          :message-type="showErrors && !item.alias.trim() ? 'error' : 'info'"
        />
        <Button
          icon="i-lucide-trash-2"
          slate
          ghost
          sm
          :aria-label="t('ARROYO.SETTINGS.FOLLOW_UP.ALIASES.REMOVE')"
          :data-testid="`remove-alias-${index}`"
          @click="removeAlias(index)"
        />
      </div>
      <p
        v-if="showErrors"
        role="alert"
        class="mb-0 text-body-main text-n-ruby-11"
      >
        {{ t('ARROYO.SETTINGS.FOLLOW_UP.ALIASES.INVALID') }}
      </p>
      <div>
        <Button
          :label="t('ARROYO.SETTINGS.FOLLOW_UP.ALIASES.ADD')"
          icon="i-lucide-plus"
          slate
          faded
          sm
          data-testid="add-alias"
          @click="addAlias"
        />
      </div>
    </div>
  </SectionCard>
</template>
