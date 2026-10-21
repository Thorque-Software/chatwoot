export const COHORT_STATES = [
  'bot',
  'unassigned',
  'pending',
  'in_progress',
  'won',
  'lost',
  'inactive',
  'unknown',
];
export const SUMMARY_METRICS = ['received', 'pending', 'bot', 'won'];
// Canvas needs resolved colors; these match the existing n-blue/violet/iris/teal tokens.
export const SELLER_PALETTE = [
  {
    color: 'rgb(39, 129, 246)',
    avatar: 'bg-n-blue-3 text-n-blue-11',
    dot: 'bg-n-blue-9',
  },
  {
    color: 'rgb(110, 86, 207)',
    avatar: 'bg-n-violet-3 text-n-violet-11',
    dot: 'bg-n-violet-9',
  },
  {
    color: 'rgb(91, 91, 214)',
    avatar: 'bg-n-iris-3 text-n-iris-11',
    dot: 'bg-n-iris-9',
  },
  {
    color: 'rgb(18, 165, 148)',
    avatar: 'bg-n-teal-3 text-n-teal-11',
    dot: 'bg-n-teal-9',
  },
];
export const sellerPresentation = (id, sellerIds) => {
  const index = sellerIds.indexOf(id);
  return SELLER_PALETTE[(index < 0 ? id : index) % SELLER_PALETTE.length];
};
export const ACTIVITY_METRICS = ['received', 'assigned', 'attended', 'won'];
export const RELATED_METRICS = [
  'repeat_sales',
  'post_sale_replies',
  'post_sale_issues',
];
