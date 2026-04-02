import type { ConfigSectionProps } from './configTypes';

export function OutputSection({ val, checked, handleChange }: ConfigSectionProps) {
  return (
    <section className="settings-section">
      <div className="settings-section-header">
        <span className="settings-section-icon">📄</span>
        <div>
          <h3 className="settings-section-title">Output &amp; Paper</h3>
          <p className="settings-section-desc">Paper reader and output format</p>
        </div>
      </div>

      <div className="settings-inline-row">
        <label className="settings-field">
          <span className="settings-field-label">Output format</span>
          <select name="output_format" value={val('output_format') || 'latex'} onChange={(e) => handleChange('output_format', e.target.value)}>
            <option value="latex">LaTeX</option>
            <option value="markdown">Markdown</option>
          </select>
        </label>
        <label className="settings-field">
          <span className="settings-field-label">Coarse read papers</span>
          <input type="number" name="paper_reader_abstract_papers" min={1} max={20} value={val('paper_reader_abstract_papers')} onChange={(e) => handleChange('paper_reader_abstract_papers', e.target.value)} />
        </label>
        <label className="settings-field">
          <span className="settings-field-label">Deep read papers</span>
          <input type="number" name="paper_reader_pdf_papers" min={0} max={20} value={val('paper_reader_pdf_papers')} onChange={(e) => handleChange('paper_reader_pdf_papers', e.target.value)} />
        </label>
      </div>

      <label className="switch-field">
        <span className="switch-field-copy"><strong>PDF deep read</strong> — download and parse full PDFs from arXiv</span>
        <span className="switch-control">
          <input type="checkbox" name="paper_reader_use_pdf" checked={checked('paper_reader_use_pdf')} onChange={(e) => handleChange('paper_reader_use_pdf', e.target.checked)} />
          <span className="switch-slider" aria-hidden="true" />
        </span>
      </label>
    </section>
  );
}
