import { useState, useEffect } from 'react';

export function useElapsedTimer(fromTimestamp: Date | null): number {
  const [elapsed, setElapsed] = useState(0);

  useEffect(() => {
    if (!fromTimestamp) {
      setElapsed(0);
      return;
    }
    const tick = () => {
      setElapsed(Math.round((Date.now() - fromTimestamp.getTime()) / 1000));
    };
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, [fromTimestamp]);

  return elapsed;
}
