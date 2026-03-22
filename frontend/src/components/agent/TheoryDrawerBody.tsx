import type { Artifacts } from '@/types';
import { ProofPanel } from '@/components/workspace/ProofPanel';

interface TheoryDrawerBodyProps {
  arts: Artifacts;
}

export function TheoryDrawerBody({ arts }: TheoryDrawerBodyProps) {
  const ts = arts.theory_state;
  if (!ts) {
    return (
      <div className="drawer-empty-state">
        <span>📐</span>
        <p>The proof hasn't started yet — the theorem sketch will appear here once the theory agent begins its work.</p>
      </div>
    );
  }
  return <ProofPanel run={null} theoryState={ts} />;
}
