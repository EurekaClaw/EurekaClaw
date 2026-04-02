import type { ConfigSectionProps } from './configTypes';

const GATE_MODES = [
  { key: 'auto', label: 'Smart', desc: 'Pause when confidence is low' },
  { key: 'human', label: 'Always review', desc: 'Pause at every gate' },
  { key: 'none', label: 'Autonomous', desc: 'Fully automatic, no pauses' },
] as const;

export function PipelineSection({ val, handleChange }: ConfigSectionProps) {
  return (
    <section className="settings-section">
      <div className="settings-section-header">
        <span className="settings-section-icon">⚙</span>
        <div>
          <h3 className="settings-section-title">Pipeline</h3>
          <p className="settings-section-desc">Control how EurekaClaw runs proofs</p>
        </div>
      </div>

      <div className="settings-inline-row">
        <label className="settings-field">
          <span className="settings-field-label">Theory pipeline</span>
          <select name="theory_pipeline" value={val('theory_pipeline') || 'default'} onChange={(e) => handleChange('theory_pipeline', e.target.value)}>
            <option value="default">Default</option>
            <option value="memory_guided">Memory-guided</option>
          </select>
        </label>
        <label className="settings-field">
          <span className="settings-field-label">Max iterations</span>
          <input type="number" name="theory_max_iterations" min={1} value={val('theory_max_iterations')} onChange={(e) => handleChange('theory_max_iterations', e.target.value)} />
        </label>
      </div>

      <div className="settings-card-group">
        <p className="settings-field-label">Human-in-the-loop</p>
        <div className="settings-card-row">
          {GATE_MODES.map((g) => (
            <button
              key={g.key}
              type="button"
              className={`settings-option-card${(val('gate_mode') || 'auto') === g.key ? ' is-active' : ''}`}
              onClick={() => handleChange('gate_mode', g.key)}
            >
              <span className="settings-option-label">{g.label}</span>
              <span className="settings-option-desc">{g.desc}</span>
            </button>
          ))}
        </div>
      </div>

      <label className="settings-field">
        <span className="settings-field-label">Experiment mode</span>
        <select name="experiment_mode" value={val('experiment_mode') || 'auto'} onChange={(e) => handleChange('experiment_mode', e.target.value)}>
          <option value="auto">Auto — run when quantitative bounds found</option>
          <option value="true">Always run validation</option>
          <option value="false">Skip validation</option>
        </select>
      </label>
    </section>
  );
}
