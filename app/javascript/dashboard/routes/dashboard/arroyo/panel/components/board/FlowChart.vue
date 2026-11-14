<script setup>
import { computed, ref } from 'vue';
import { useResizeObserver } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { nodeColor, linkColor } from './boardColors';

// Embudo de izquierda a derecha (Sankey): origen → a quién le toca → en qué quedó.
// Los datos llegan armados del backend (Arroyo::Commercial::BoardFlow); acá solo se dibujan.
const props = defineProps({
  flow: { type: Object, required: true },
  sellerIds: { type: Array, default: () => [] },
  nodeLabel: { type: Function, required: true },
  stuck: { type: Array, default: () => ['pending', 'abandoned'] },
  columnLabels: { type: Array, default: () => [] },
});
const emit = defineEmits(['select']);
const { t } = useI18n();

const root = ref(null);
const width = ref(720);
useResizeObserver(root, entries => {
  width.value = Math.max(entries[0].contentRect.width, 640);
});

const NODE_WIDTH = 12;
const GAP = 14;
const SIDE = 170;
const TOP = 8;
const hovered = ref(null);

const columns = computed(() =>
  [0, 1, 2].map(column =>
    props.flow.nodes.filter(node => node.column === column)
  )
);
const height = computed(() =>
  Math.max(260, Math.max(...columns.value.map(col => col.length)) * 44)
);
const xFor = column =>
  [SIDE, (width.value - NODE_WIDTH) / 2, width.value - SIDE - NODE_WIDTH][
    column
  ];

const layout = computed(() => {
  const inner = height.value - TOP * 2;
  const scales = columns.value
    .filter(col => col.length)
    .map(
      col =>
        (inner - GAP * (col.length - 1)) /
        col.reduce((sum, node) => sum + node.value, 0)
    );
  const scale = scales.length ? Math.min(...scales) : 1;
  const nodes = {};
  columns.value.forEach(col => {
    let y = TOP;
    col.forEach(node => {
      const size = Math.max(node.value * scale, 3);
      nodes[node.id] = {
        ...node,
        x: xFor(node.column),
        y,
        height: size,
        out: 0,
        in: 0,
      };
      y += size + GAP;
    });
  });
  const order = id => nodes[id]?.y ?? 0;
  const links = [...props.flow.links]
    .filter(link => nodes[link.source] && nodes[link.target])
    .sort(
      (a, b) =>
        order(a.source) - order(b.source) || order(a.target) - order(b.target)
    )
    .map(link => ({ ...link, thickness: Math.max(link.value * scale, 1) }));
  links.forEach(link => {
    link.sy = nodes[link.source].y + nodes[link.source].out;
    nodes[link.source].out += link.thickness;
  });
  [...links]
    .sort(
      (a, b) =>
        order(a.target) - order(b.target) || order(a.source) - order(b.source)
    )
    .forEach(link => {
      link.ty = nodes[link.target].y + nodes[link.target].in;
      nodes[link.target].in += link.thickness;
    });
  return { nodes: Object.values(nodes), links, scale };
});

const linkPath = link => {
  const x0 = xFor(layout.value.nodes.find(n => n.id === link.source).column);
  const x1 = xFor(layout.value.nodes.find(n => n.id === link.target).column);
  const start = x0 + NODE_WIDTH;
  const middle = (start + x1) / 2;
  const y0 = link.sy + link.thickness / 2;
  const y1 = link.ty + link.thickness / 2;
  return `M${start},${y0} C${middle},${y0} ${middle},${y1} ${x1},${y1}`;
};

const nodeById = id => layout.value.nodes.find(node => node.id === id);
const linkTitle = link =>
  `${props.nodeLabel(nodeById(link.source))} → ${props.nodeLabel(nodeById(link.target))}: ${link.value}`;

const isActive = link =>
  !hovered.value ||
  link.source === hovered.value ||
  link.target === hovered.value;

const truncate = (text, size = 24) =>
  text.length > size ? `${text.slice(0, size - 1)}…` : text;

const isStuck = node =>
  node.kind === 'stage' && props.stuck.includes(node.key) && node.value > 0;

const labelX = node => {
  if (node.column === 0) return node.x - 8;
  return node.x + NODE_WIDTH + 8;
};
const anchor = node => (node.column === 0 ? 'end' : 'start');

const onKey = (event, node) => {
  if (['Enter', ' '].includes(event.key)) {
    event.preventDefault();
    emit('select', node);
  }
};
</script>

<template>
  <div ref="root" class="w-full min-w-0 overflow-x-auto overscroll-x-contain">
    <!-- Los títulos van dentro del área que se desplaza para quedar alineados con el gráfico en celular. -->
    <div
      v-if="columnLabels.length"
      class="mb-2 grid grid-cols-3 px-1 text-label-small font-medium uppercase tracking-wide text-n-slate-10"
      :style="{ width: `${width}px` }"
      aria-hidden="true"
    >
      <span>{{ columnLabels[0] }}</span>
      <span class="text-center">{{ columnLabels[1] }}</span>
      <span class="text-end">{{ columnLabels[2] }}</span>
    </div>
    <svg
      :width="width"
      :height="height"
      :viewBox="`0 0 ${width} ${height}`"
      role="group"
      :aria-label="t('ARROYO.PANEL.BOARD.FLOW.ARIA')"
      class="block select-none"
      data-testid="board-flow"
    >
      <g fill="none">
        <path
          v-for="link in layout.links"
          :key="`${link.source}-${link.target}`"
          :d="linkPath(link)"
          :stroke="linkColor(link, layout.nodes, sellerIds)"
          :stroke-width="link.thickness"
          :stroke-opacity="isActive(link) ? 0.45 : 0.08"
          class="transition-[stroke-opacity] duration-150"
        >
          <title>{{ linkTitle(link) }}</title>
        </path>
      </g>
      <g
        v-for="node in layout.nodes"
        :key="node.id"
        role="button"
        tabindex="0"
        class="cursor-pointer outline-none focus-visible:[&>rect]:stroke-n-blue-11"
        :aria-label="`${nodeLabel(node)}: ${node.value}`"
        :data-testid="`flow-node-${node.id}`"
        @mouseenter="hovered = node.id"
        @mouseleave="hovered = null"
        @focus="hovered = node.id"
        @blur="hovered = null"
        @click="emit('select', node)"
        @keydown="onKey($event, node)"
      >
        <rect
          :x="node.x"
          :y="node.y"
          :width="NODE_WIDTH"
          :height="node.height"
          rx="3"
          :fill="nodeColor(node, sellerIds, layout.nodes)"
          :stroke-width="isStuck(node) ? 3 : 2"
          :class="isStuck(node) ? 'stroke-n-amber-9' : 'stroke-transparent'"
        />
        <text
          :x="labelX(node)"
          :y="node.y + node.height / 2"
          :text-anchor="anchor(node)"
          dominant-baseline="middle"
          class="fill-n-slate-12 stroke-n-solid-2 text-[12px] [paint-order:stroke] [stroke-width:4px]"
        >
          <title>{{ nodeLabel(node) }}</title>
          {{ truncate(nodeLabel(node)) }}
          <tspan
            class="font-semibold"
            :class="isStuck(node) ? 'fill-n-amber-11' : 'fill-n-slate-11'"
            dx="6"
          >
            {{ node.value }}
          </tspan>
        </text>
      </g>
    </svg>
  </div>
</template>
