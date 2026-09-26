export type CostsPeriod = "7d" | "30d" | "90d" | "12m";

export interface SpendingUsage {
  requestCount: number;
  inputTokens: number;
  outputTokens: number;
  totalCostUSD: number;
  estimatedCostUSD: number;
}

export interface SpendingDay {
  day: string;
  usage: SpendingUsage;
}

export interface SpendingBucket {
  key: string;
  label: string;
  usage: SpendingUsage;
}

export const COSTS_PERIODS: { id: CostsPeriod; label: string }[] = [
  { id: "7d", label: "7 days" },
  { id: "30d", label: "30 days" },
  { id: "90d", label: "90 days" },
  { id: "12m", label: "12 months" }
];

const zeroUsage = (): SpendingUsage => ({
  requestCount: 0,
  inputTokens: 0,
  outputTokens: 0,
  totalCostUSD: 0,
  estimatedCostUSD: 0
});

const nonNegative = (value: unknown) => {
  const number = Number(value);
  return Number.isFinite(number) ? Math.max(0, number) : 0;
};

export function normalizeSpendingUsage(value: unknown): SpendingUsage {
  const item = value && typeof value === "object" ? value as Record<string, unknown> : {};
  const totalCostUSD = nonNegative(item.totalCostUSD);
  return {
    requestCount: nonNegative(item.requestCount),
    inputTokens: nonNegative(item.inputTokens),
    outputTokens: nonNegative(item.outputTokens),
    totalCostUSD,
    estimatedCostUSD: Math.min(totalCostUSD, nonNegative(item.estimatedCostUSD))
  };
}

export function costsPeriodRange(period: CostsPeriod, now = new Date()) {
  const from = new Date(now);
  from.setUTCHours(0, 0, 0, 0);
  if (period === "12m") {
    from.setUTCDate(1);
    from.setUTCMonth(from.getUTCMonth() - 11);
  } else {
    from.setUTCDate(from.getUTCDate() - (period === "7d" ? 6 : period === "30d" ? 29 : 89));
  }
  return { from: from.toISOString(), to: now.toISOString() };
}

function dayKey(date: Date) {
  return date.toISOString().slice(0, 10);
}

function bucketKey(day: string, period: CostsPeriod) {
  if (period === "12m") return day.slice(0, 7);
  if (period !== "90d") return day;
  const date = new Date(`${day}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) return day;
  date.setUTCDate(date.getUTCDate() - ((date.getUTCDay() + 6) % 7));
  return dayKey(date);
}

function bucketLabel(key: string, period: CostsPeriod) {
  const date = new Date(`${period === "12m" ? `${key}-01` : key}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) return key;
  return new Intl.DateTimeFormat(undefined, {
    timeZone: "UTC",
    month: "short",
    ...(period === "12m" ? { year: "numeric" } : { day: "numeric" })
  }).format(date);
}

export function spendingBuckets(days: SpendingDay[], period: CostsPeriod, now = new Date()): SpendingBucket[] {
  const { from } = costsPeriodRange(period, now);
  const start = new Date(from);
  const end = new Date(now);
  const byKey = new Map<string, SpendingUsage>();

  if (period === "12m") {
    const cursor = new Date(start);
    while (cursor <= end) {
      byKey.set(dayKey(cursor).slice(0, 7), zeroUsage());
      cursor.setUTCMonth(cursor.getUTCMonth() + 1);
    }
  } else {
    const cursor = new Date(start);
    while (cursor <= end) {
      const key = bucketKey(dayKey(cursor), period);
      if (!byKey.has(key)) byKey.set(key, zeroUsage());
      cursor.setUTCDate(cursor.getUTCDate() + 1);
    }
  }

  for (const item of days) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(item.day)) continue;
    const key = bucketKey(item.day, period);
    const bucket = byKey.get(key);
    if (!bucket) continue;
    const usage = normalizeSpendingUsage(item.usage);
    bucket.requestCount += usage.requestCount;
    bucket.inputTokens += usage.inputTokens;
    bucket.outputTokens += usage.outputTokens;
    bucket.totalCostUSD += usage.totalCostUSD;
    bucket.estimatedCostUSD += usage.estimatedCostUSD;
  }

  return [...byKey.entries()].map(([key, usage]) => ({ key, label: bucketLabel(key, period), usage }));
}

export function formatSpendingUSD(value: number) {
  if (!Number.isFinite(value) || value <= 0) return "$0.00";
  if (value < 0.01) {
    const precision = value < 0.000001 ? 10 : 8;
    return `$${value.toFixed(precision).replace(/(\.\d*?)0+$/, "$1").replace(/\.$/, ".00")}`;
  }
  if (value < 1) return `$${value.toFixed(4)}`;
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(value);
}
