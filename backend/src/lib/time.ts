/**
 * Timezone helpers. Stores live in their own timezone, so "today", hourly charts
 * and end-of-day reports are computed in store-local time, not server time.
 */

const formatters = new Map<string, Intl.DateTimeFormat>();

function formatter(timeZone: string) {
  let f = formatters.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', {
      timeZone,
      hourCycle: 'h23',
      weekday: 'short',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
    formatters.set(timeZone, f);
  }
  return f;
}

export interface ZonedParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
  weekday: string; // mon, tue…
}

export function zonedParts(date: Date, timeZone: string): ZonedParts {
  const out: Record<string, string> = {};
  for (const p of formatter(timeZone).formatToParts(date)) out[p.type] = p.value;
  return {
    year: Number(out.year),
    month: Number(out.month),
    day: Number(out.day),
    hour: Number(out.hour) % 24,
    minute: Number(out.minute),
    second: Number(out.second),
    weekday: (out.weekday ?? 'Mon').slice(0, 3).toLowerCase(),
  };
}

const pad = (n: number) => String(n).padStart(2, '0');

export function localDate(date: Date, timeZone: string): string {
  const p = zonedParts(date, timeZone);
  return `${p.year}-${pad(p.month)}-${pad(p.day)}`;
}

export function localHour(date: Date, timeZone: string): number {
  return zonedParts(date, timeZone).hour;
}

export function localMinutesOfDay(date: Date, timeZone: string): number {
  const p = zonedParts(date, timeZone);
  return p.hour * 60 + p.minute;
}

function offsetMs(date: Date, timeZone: string): number {
  const p = zonedParts(date, timeZone);
  const asUtc = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
  return asUtc - Math.floor(date.getTime() / 1000) * 1000;
}

/** UTC instant of local midnight for a YYYY-MM-DD date in `timeZone` (DST safe). */
export function startOfLocalDay(dateStr: string, timeZone: string): Date {
  const [y, m, d] = dateStr.split('-').map(Number) as [number, number, number];
  const guess = Date.UTC(y, m - 1, d);
  let ts = guess - offsetMs(new Date(guess), timeZone);
  ts = guess - offsetMs(new Date(ts), timeZone);
  return new Date(ts);
}

export function addDays(dateStr: string, days: number): string {
  const [y, m, d] = dateStr.split('-').map(Number) as [number, number, number];
  const t = new Date(Date.UTC(y, m - 1, d + days));
  return `${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}`;
}

export function daysBetween(from: string, to: string): number {
  const a = Date.parse(`${from}T00:00:00Z`);
  const b = Date.parse(`${to}T00:00:00Z`);
  return Math.round((b - a) / 86400000);
}

export type WeeklyHours = Record<string, [string, string] | null>;

const toMinutes = (hhmm: string) => {
  const [h, m] = hhmm.split(':').map(Number) as [number, number];
  return h * 60 + m;
};

const DAYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];

/** True when the store is open at `now`. Handles closing times after midnight ("02:00"). */
export function isOpenAt(hours: WeeklyHours, timeZone: string, now = new Date()): boolean {
  const p = zonedParts(now, timeZone);
  const minutes = p.hour * 60 + p.minute;
  const today = hours[p.weekday];
  if (today) {
    const open = toMinutes(today[0]);
    const close = toMinutes(today[1]);
    if (close > open ? minutes >= open && minutes < close : minutes >= open) return true;
  }
  const yesterdayKey = DAYS[(DAYS.indexOf(p.weekday) + 6) % 7]!;
  const yesterday = hours[yesterdayKey];
  if (yesterday) {
    const open = toMinutes(yesterday[0]);
    const close = toMinutes(yesterday[1]);
    if (close <= open && minutes < close) return true;
  }
  return false;
}

export function hoursLabel(hours: WeeklyHours, timeZone: string, now = new Date()): string {
  const today = hours[zonedParts(now, timeZone).weekday];
  if (!today) return 'Closed today';
  const fmt = (hhmm: string) => {
    const [h, m] = hhmm.split(':').map(Number) as [number, number];
    const suffix = h >= 12 && h < 24 ? 'PM' : 'AM';
    const h12 = h % 12 === 0 ? 12 : h % 12;
    return `${h12}${m ? `:${pad(m)}` : ''} ${suffix}`;
  };
  return `${fmt(today[0])} – ${fmt(today[1])}`;
}
