import { sellerPresentation } from '../../commercialConstants';

// Colores del embudo del panel. Se usan las variables de la paleta de Chatwoot para que
// respeten el modo claro y oscuro (los vendedores mantienen los colores del panel actual).
const token = name => `rgb(var(--${name}))`;

const ORIGIN_COLORS = [
  'blue-9',
  'violet-9',
  'teal-9',
  'iris-9',
  'amber-9',
  'ruby-9',
].map(token);

export const STAGE_COLORS = {
  bot: token('violet-9'),
  unassigned: token('gray-9'),
  pending: token('amber-9'),
  in_progress: token('blue-9'),
  inactive: token('slate-9'),
  abandoned: token('ruby-9'),
  lost: token('slate-10'),
  won: token('teal-9'),
};

const ORGANIC_COLOR = token('gray-9');
const OTHER_COLOR = token('slate-8');

const originColor = (node, nodes) => {
  if (node.key === 'organic') return ORGANIC_COLOR;
  if (node.key === 'other') return OTHER_COLOR;
  const ranked = nodes.filter(
    item => item.column === 0 && !['organic', 'other'].includes(item.key)
  );
  const index = ranked.findIndex(item => item.id === node.id);
  return ORIGIN_COLORS[Math.max(index, 0) % ORIGIN_COLORS.length];
};

export const nodeColor = (node, sellerIds, nodes) => {
  if (node.kind === 'origin') return originColor(node, nodes);
  if (node.kind === 'seller')
    return sellerPresentation(Number(node.key), sellerIds).color;
  if (node.kind === 'stage') return STAGE_COLORS[node.key];
  return STAGE_COLORS[node.kind] || OTHER_COLOR;
};

// Las bandas toman el color del nodo de la izquierda: así se sigue cada origen hasta el vendedor
// y cada vendedor hasta el resultado.
export const linkColor = (link, nodes, sellerIds) => {
  const source = nodes.find(node => node.id === link.source);
  return source ? nodeColor(source, sellerIds, nodes) : OTHER_COLOR;
};
