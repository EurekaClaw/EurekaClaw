import { useState, useCallback } from 'react';
import type { SessionRun } from '@/types';
import { titleCase, humanize } from '@/lib/formatters';
import { apiPost } from '@/api/client';

interface PaperPanelProps {
  run: SessionRun | null;
}

interface CompileResponse {
  ok?: boolean;
  error?: string;
  pdf_path?: string;
}

export function PaperPanel({ run }: PaperPanelProps) {
  const theoryState = run?.artifacts?.theory_state;
  const result = run?.result;
  const selDir = run?.artifacts?.research_brief?.selected_direction;
  const title = humanize(selDir?.title || selDir?.hypothesis?.slice(0, 80) || 'EurekaClaw Autonomous Research System');
  const paperText = result?.latex_paper || '';
  const pdfPath = result?.pdf_path;
  const outputDir = run?.output_dir;
  const isCompleted = run?.status === 'completed';
  const isRunning = run?.status === 'running';
  const isFailed = run?.status === 'failed';

  const [latexOpen, setLatexOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const [compiling, setCompiling] = useState(false);
  const [compileMsg, setCompileMsg] = useState('');
  const [compileMsgError, setCompileMsgError] = useState(false);
  const [hasPdf, setHasPdf] = useState(!!pdfPath);

  // Check if PDF exists on first render when output_dir is available
  const checkPdfExists = useCallback(async () => {
    if (!run?.run_id) return;
    try {
      const resp = await fetch(`/api/runs/${run.run_id}/artifacts/paper.pdf`, { method: 'HEAD' });
      setHasPdf(resp.ok);
    } catch {
      // ignore
    }
  }, [run?.run_id]);

  // Run check once when component mounts with a completed run
  useState(() => {
    if (isCompleted && outputDir) void checkPdfExists();
  });

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(paperText);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // fallback
      const ta = document.createElement('textarea');
      ta.value = paperText;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  const handleCompilePdf = async () => {
    if (!run?.run_id) return;
    setCompiling(true);
    setCompileMsg('');
    setCompileMsgError(false);
    try {
      const resp = await apiPost<CompileResponse>(`/api/runs/${run.run_id}/compile-pdf`, {});
      if (resp.ok) {
        setCompileMsg('PDF compiled successfully');
        setHasPdf(true);
      } else {
        setCompileMsg(resp.error || 'Compilation failed');
        setCompileMsgError(true);
      }
    } catch (err) {
      setCompileMsg((err as Error).message || 'Compilation failed');
      setCompileMsgError(true);
    } finally {
      setCompiling(false);
    }
  };

  const handleDownloadPdf = () => {
    if (!run?.run_id) return;
    window.open(`/api/runs/${run.run_id}/artifacts/paper.pdf`, '_blank');
  };

  const handleDownloadTex = () => {
    if (!run?.run_id) return;
    window.open(`/api/runs/${run.run_id}/artifacts/paper.tex`, '_blank');
  };

  const handleDownloadBib = () => {
    if (!run?.run_id) return;
    window.open(`/api/runs/${run.run_id}/artifacts/references.bib`, '_blank');
  };

  // Status summary
  let summary = 'Launch a session to produce a real paper draft and final run summary.';
  if (isCompleted) {
    summary = paperText
      ? ''
      : 'The run completed and output artifacts are available, but no paper text was returned.';
  } else if (isRunning) {
    summary = 'The writer surface will populate as the pipeline produces theory and experiment artifacts.';
  } else if (isFailed) {
    summary = run?.error || 'The run failed before a paper could be generated.';
  }

  const provenCount = Object.keys(theoryState?.proven_lemmas || {}).length;
  const openCount = (theoryState?.open_goals || []).length;

  return (
    <div className="paper-preview" id="paper-preview">
      <div className="paper-sheet">
        <div className="paper-header-row">
          <div className="paper-header-left">
            <p className="paper-title">{title}</p>
            <p className="paper-meta">
              <span className={`paper-status-badge paper-status-badge--${run?.status || 'queued'}`}>
                {titleCase(run?.status || 'not started')}
              </span>
              {theoryState && (
                <span className="paper-theory-stats">
                  <span className="paper-stat paper-stat--ok">{provenCount} proven</span>
                  {openCount > 0 && <span className="paper-stat paper-stat--open">{openCount} open</span>}
                </span>
              )}
            </p>
          </div>
          {isCompleted && outputDir && (
            <p className="paper-output-dir">
              <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
              <code>{outputDir}</code>
            </p>
          )}
        </div>

        {summary && <p className="paper-summary">{summary}</p>}

        {/* Action buttons */}
        {isCompleted && paperText && (
          <div className="paper-actions-row">
            {hasPdf ? (
              <button className="paper-action-btn paper-action-btn--primary" onClick={handleDownloadPdf}>
                <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
                Download PDF
              </button>
            ) : (
              <button
                className="paper-action-btn paper-action-btn--primary"
                onClick={handleCompilePdf}
                disabled={compiling}
              >
                {compiling ? (
                  <>
                    <span className="paper-spinner" />
                    Compiling…
                  </>
                ) : (
                  <>
                    <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/></svg>
                    Generate PDF
                  </>
                )}
              </button>
            )}
            <button className="paper-action-btn paper-action-btn--secondary" onClick={handleDownloadTex}>
              <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
              .tex
            </button>
            <button className="paper-action-btn paper-action-btn--secondary" onClick={handleDownloadBib}>
              <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
              .bib
            </button>
            {compileMsg && (
              <span className={`paper-compile-msg${compileMsgError ? ' is-error' : ''}`}>
                {compileMsg}
              </span>
            )}
          </div>
        )}

        {/* LaTeX source code collapsible */}
        {paperText && (
          <div className="paper-latex-section">
            <button
              className="paper-latex-toggle"
              onClick={() => setLatexOpen(!latexOpen)}
              aria-expanded={latexOpen}
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="12" height="12"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2.5"
                strokeLinecap="round"
                strokeLinejoin="round"
                className={`paper-latex-chevron${latexOpen ? ' is-open' : ''}`}
              >
                <polyline points="9 18 15 12 9 6" />
              </svg>
              <span>LaTeX Source</span>
              <span className="paper-latex-size">{(paperText.length / 1024).toFixed(1)} KB</span>
            </button>
            {latexOpen && (
              <div className="paper-latex-viewer">
                <div className="paper-latex-toolbar">
                  <button className="paper-copy-btn" onClick={handleCopy}>
                    {copied ? (
                      <>
                        <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
                        Copied!
                      </>
                    ) : (
                      <>
                        <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
                        Copy LaTeX
                      </>
                    )}
                  </button>
                </div>
                <pre className="paper-latex-code"><code>{paperText}</code></pre>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
