import type { ConfigSectionProps } from './configTypes';

const SLIDER_KEYS = [
  { name: 'max_tokens_agent', label: 'Agent loop', min: 1024, max: 20480, step: 512 },
  { name: 'max_tokens_prover', label: 'Prover', min: 512, max: 20480, step: 256 },
  { name: 'max_tokens_planner', label: 'Planner', min: 512, max: 16384, step: 256 },
  { name: 'max_tokens_architect', label: 'Architect', min: 512, max: 16384, step: 256 },
  { name: 'max_tokens_decomposer', label: 'Decomposer', min: 256, max: 16384, step: 256 },
  { name: 'max_tokens_assembler', label: 'Assembler', min: 512, max: 20480, step: 256 },
  { name: 'max_tokens_formalizer', label: 'Formalizer / Refiner', min: 256, max: 16384, step: 256 },
  { name: 'max_tokens_crystallizer', label: 'TheoremCrystallizer', min: 256, max: 20480, step: 256 },
  { name: 'max_tokens_analyst', label: 'Analyst', min: 256, max: 16384, step: 256 },
  { name: 'max_tokens_sketch', label: 'Sketch', min: 256, max: 8192, step: 256 },
  { name: 'max_tokens_verifier', label: 'Verifier', min: 128, max: 16384, step: 128 },
  { name: 'max_tokens_compress', label: 'Context compress', min: 128, max: 4096, step: 128 },
] as const;

export function AdvancedSection({ val, handleChange }: ConfigSectionProps) {
  return (
    <section className="settings-section">
      <div className="settings-section-header">
        <span className="settings-section-icon">🔧</span>
        <div>
          <h3 className="settings-section-title">Advanced</h3>
          <p className="settings-section-desc">Confidence thresholds, directories, and token limits</p>
        </div>
      </div>

      <div className="settings-inline-row">
        <label className="settings-field">
          <span className="settings-field-label">Auto-verify confidence</span>
          <input type="number" name="auto_verify_confidence" min={0} max={1} step={0.01} value={val('auto_verify_confidence')} onChange={(e) => handleChange('auto_verify_confidence', e.target.value)} />
        </label>
        <label className="settings-field">
          <span className="settings-field-label">Verifier pass confidence</span>
          <input type="number" name="verifier_pass_confidence" min={0} max={1} step={0.01} value={val('verifier_pass_confidence')} onChange={(e) => handleChange('verifier_pass_confidence', e.target.value)} />
        </label>
      </div>

      <label className="settings-field">
        <span className="settings-field-label">Data directory</span>
        <input type="text" name="eurekaclaw_dir" placeholder="~/.eurekaclaw" value={val('eurekaclaw_dir')} onChange={(e) => handleChange('eurekaclaw_dir', e.target.value)} />
      </label>

      <details className="settings-details">
        <summary>Token limits per agent</summary>
        <fieldset className="token-limits-group">
          {SLIDER_KEYS.map(({ name, label, min, max, step }) => (
            <label key={name} className="slider-label">
              <span>{label} <em id={`${name}-val`}>{val(name)}</em></span>
              <input
                type="range"
                name={name}
                min={min}
                max={max}
                step={step}
                value={val(name) || String(min)}
                onChange={(e) => handleChange(name, e.target.value)}
              />
            </label>
          ))}
        </fieldset>
      </details>
    </section>
  );
}
