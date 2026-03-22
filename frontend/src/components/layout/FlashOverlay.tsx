import { useEffect, useRef } from 'react';
import { useUiStore } from '@/store/uiStore';

export function FlashOverlay() {
  const isFlashing = useUiStore((s) => s.isFlashing);
  const overlayRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = overlayRef.current;
    if (!el) return;
    if (isFlashing) {
      el.classList.remove('flash-in', 'flash-out');
      requestAnimationFrame(() => {
        el.classList.add('flash-in');
        setTimeout(() => {
          el.classList.remove('flash-in');
          el.classList.add('flash-out');
          setTimeout(() => el.classList.remove('flash-out'), 380);
        }, 90);
      });
    }
  }, [isFlashing]);

  return <div id="flash-overlay" ref={overlayRef} aria-hidden="true" />;
}
