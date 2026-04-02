import { useState } from 'react';

interface CollapsibleSectionProps {
  title: string;
  count?: number;
  defaultOpen?: boolean;
  children: React.ReactNode;
}

export function CollapsibleSection({ title, count, defaultOpen = false, children }: CollapsibleSectionProps) {
  const [isOpen, setIsOpen] = useState(defaultOpen);

  return (
    <div className="drawer-section">
      <button
        type="button"
        className="drawer-section-toggle"
        onClick={() => setIsOpen((open) => !open)}
      >
        <span className="drawer-section-toggle-title">
          <span className={`drawer-section-toggle-caret${isOpen ? ' is-open' : ''}`} aria-hidden="true">
            ▾
          </span>
          <h4>{title}</h4>
          {count !== undefined && <span className="drawer-section-toggle-count">{count}</span>}
        </span>
      </button>
      {isOpen && children}
    </div>
  );
}
