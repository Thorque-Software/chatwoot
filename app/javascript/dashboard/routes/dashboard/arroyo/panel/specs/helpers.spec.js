import { presetRange, periodRange, parseIds } from '../helpers';

describe('presetRange', () => {
  const today = '2026-10-06';

  it.each([
    ['today', { since: '2026-10-06', until: '2026-10-06' }],
    ['yesterday', { since: '2026-10-05', until: '2026-10-05' }],
    ['last_7_days', { since: '2026-09-30', until: '2026-10-06' }],
    ['this_month', { since: '2026-10-01', until: '2026-10-06' }],
    ['last_month', { since: '2026-09-01', until: '2026-09-30' }],
  ])('returns the range for %s', (preset, range) => {
    expect(presetRange(preset, today)).toEqual(range);
  });
});

describe('periodRange', () => {
  const filters = { since: '2026-10-01', until: '2026-10-09' };

  it('returns the single day when grouping by day', () => {
    expect(periodRange('2026-10-03', 'day', filters)).toEqual({
      since: '2026-10-03',
      until: '2026-10-03',
    });
  });

  it('clamps the week to the filtered range', () => {
    expect(periodRange('2026-09-28', 'week', filters)).toEqual({
      since: '2026-10-01',
      until: '2026-10-04',
    });
    expect(periodRange('2026-10-05', 'week', filters)).toEqual({
      since: '2026-10-05',
      until: '2026-10-09',
    });
  });
});

describe('parseIds', () => {
  it('parses comma separated ids from the URL', () => {
    expect(parseIds('3,7')).toEqual([3, 7]);
    expect(parseIds(undefined)).toEqual([]);
  });
});
