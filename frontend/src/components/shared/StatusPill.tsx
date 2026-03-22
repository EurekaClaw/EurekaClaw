import { statusClass } from '@/lib/statusHelpers';
import { titleCase } from '@/lib/formatters';

interface StatusPillProps {
  status: string;
  label?: string;
  className?: string;
}

export function StatusPill({ status, label, className = '' }: StatusPillProps) {
  return (
    <span className={`status-pill ${statusClass(status)} ${className}`.trim()}>
      {label ?? titleCase(status)}
    </span>
  );
}
