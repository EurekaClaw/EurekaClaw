import type { ToolStep } from '@/types';

interface ToolStepsProps {
  steps: ToolStep[];
}

export function ToolSteps({ steps }: ToolStepsProps) {
  if (!steps.length) return null;

  return (
    <div className="tool-steps">
      {steps.map((step, i) => (
        <div className="tool-step" key={i}>
          <span className={`tool-step-dot tool-step-dot--${step.status}`} />
          <span>{step.tool}: {step.input}</span>
        </div>
      ))}
    </div>
  );
}
