import {
  addDays,
  endOfMonth,
  format,
  parseISO,
  startOfMonth,
  subDays,
  subMonths,
} from 'date-fns';

const DATE_FORMAT = 'yyyy-MM-dd';

// Fecha de hoy en la zona horaria del negocio, no la del navegador
export const todayIn = timezone =>
  new Intl.DateTimeFormat('en-CA', { timeZone: timezone }).format(new Date());

export const presetRange = (preset, today) => {
  const date = parseISO(today);
  const toString = value => format(value, DATE_FORMAT);
  switch (preset) {
    case 'today':
      return { since: today, until: today };
    case 'yesterday':
      return {
        since: toString(subDays(date, 1)),
        until: toString(subDays(date, 1)),
      };
    case 'this_month':
      return { since: toString(startOfMonth(date)), until: today };
    case 'last_month': {
      const lastMonth = subMonths(date, 1);
      return {
        since: toString(startOfMonth(lastMonth)),
        until: toString(endOfMonth(lastMonth)),
      };
    }
    default:
      return { since: toString(subDays(date, 6)), until: today };
  }
};

// Rango de fechas que cubre un período del reporte (un día o una semana dentro del rango filtrado)
export const periodRange = (period, groupBy, filters) => {
  if (groupBy === 'day') return { since: period, until: period };

  const weekEnd = format(addDays(parseISO(period), 6), DATE_FORMAT);
  return {
    since: period < filters.since ? filters.since : period,
    until: weekEnd > filters.until ? filters.until : weekEnd,
  };
};

export const parseIds = value =>
  value ? String(value).split(',').filter(Boolean).map(Number) : [];
