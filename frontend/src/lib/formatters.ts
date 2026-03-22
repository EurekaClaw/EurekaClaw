import type { SessionRun } from '@/types';

/** Replace underscores with spaces for display. */
export function humanize(text: string): string {
  return text.replace(/_/g, ' ');
}

export function escapeHtml(value: string): string {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export function titleCase(text: string): string {
  return text
    .split('_')
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

export function truncateSessionName(run: SessionRun | null): string {
  const text = run?.input_spec?.query || run?.input_spec?.domain || 'Untitled session';
  return text.length > 64 ? text.slice(0, 61) + '…' : text;
}

export function parseServerTimestamp(value: string | undefined | null): Date | null {
  if (!value) return null;
  const normalized = /[zZ]|[+-]\d{2}:\d{2}$/.test(value) ? value : `${value}Z`;
  const parsed = new Date(normalized);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

export function formatLocalTimestamp(value: string | undefined): string {
  const parsed = parseServerTimestamp(value);
  if (!parsed) return '--';
  return parsed.toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

export function formatRelativeTime(value: string | undefined): string {
  const parsed = parseServerTimestamp(value);
  if (!parsed) return '--';
  const diffMin = Math.floor((Date.now() - parsed.getTime()) / 60000);
  if (diffMin < 1) return 'Just now';
  if (diffMin < 60) return `${diffMin}m ago`;
  const diffHr = Math.floor(diffMin / 60);
  if (diffHr < 24) return `${diffHr}h ago`;
  return `${Math.floor(diffHr / 24)}d ago`;
}
