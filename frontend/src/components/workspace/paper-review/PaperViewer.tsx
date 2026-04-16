import { useState, useCallback } from 'react';
import { apiPost } from '@/api/client';
import { RewriteOverlay } from './RewriteOverlay';
import type { SessionRun } from '@/types';

interface PaperViewerProps {
  run: SessionRun;
  paperVersion: number;
  isRewriting: boolean;
  theoryStatus: string;
  writerStatus: string;
}

interface CompileResponse {
  ok?: boolean;
  error?: string;
  pdf_path?: string;
}

export function PaperViewer({ run, paperVersion, isRewriting, theoryStatus, writerStatus }: PaperViewerProps) {
  const [activeTab, setActiveTab] = useState<'pdf' | 'latex'>('pdf');
  const [compiling, setCompiling] = useState(false);
  const [compileError, setCompileError] = useState('');
  const [compiledPdfPath, setCompiledPdfPath] = useState<string | null>(null);
  const [prevVersion, setPrevVersion] = useState(paperVersion);

  // Reset compiled PDF state when paper version changes (after rewrite)
  // so the iframe doesn't show a stale/deleted PDF.
  if (paperVersion !== prevVersion) {
    setPrevVersion(paperVersion);
    setCompiledPdfPath(null);
    setCompileError('');
  }

  // Also clear when a rewrite starts so the overlay replaces the iframe
  const [wasRewriting, setWasRewriting] = useState(isRewriting);
  if (isRewriting && !wasRewriting) {
    setCompiledPdfPath(null);
    setCompileError('');
  }
  if (isRewriting !== wasRewriting) {
    setWasRewriting(isRewriting);
  }

  // Source LaTeX from writer task outputs (available during gate) or fallback to run.result
  const writerTask = run.pipeline?.find((t) => t.name === 'writer');
  const latexSource = (writerTask?.outputs?.latex_paper as string) || run.result?.latex_paper || '';
  // Only trust compiledPdfPath (set after explicit compile action).
  // run.result?.pdf_path may point to a stale file deleted after rewrite.
  const pdfPath = compiledPdfPath;
  const lineCount = latexSource ? latexSource.split('\n').length : 0;

  const compilePdf = useCallback(async () => {
    setCompiling(true);
    setCompileError('');
    try {
      const res = await apiPost<CompileResponse>(`/api/runs/${run.run_id}/compile-pdf`, {});
      if (res.ok) {
        setCompiledPdfPath(res.pdf_path || 'compiled');
      } else {
        setCompileError(res.error || 'Compilation failed');
      }
    } catch (e) {
      setCompileError(String(e));
    } finally {
      setCompiling(false);
    }
  }, [run.run_id]);

  return (
    <div className="paper-viewer" style={{ position: 'relative' }}>
      <div className="pv-tab-bar">
        <button
          className={`pv-tab${activeTab === 'pdf' ? ' is-active' : ''}`}
          onClick={() => setActiveTab('pdf')}
        >
          PDF
        </button>
        <button
          className={`pv-tab${activeTab === 'latex' ? ' is-active' : ''}`}
          onClick={() => setActiveTab('latex')}
        >
          LaTeX
        </button>
        <div className="pv-tab-actions">
          <a
            href={`/api/runs/${run.run_id}/artifacts/paper.tex`}
            target="_blank"
            rel="noreferrer"
            className="pv-download-btn"
          >
            ⬇ .tex
          </a>
          <a
            href={`/api/runs/${run.run_id}/artifacts/paper.pdf`}
            target="_blank"
            rel="noreferrer"
            className="pv-download-btn"
          >
            ⬇ .pdf
          </a>
        </div>
      </div>

      <div className="pv-content">
        {activeTab === 'pdf' ? (
          pdfPath ? (
            <iframe
              className="pv-pdf-frame"
              src={`/api/runs/${run.run_id}/artifacts/paper.pdf`}
              title="Paper PDF"
            />
          ) : (
            <div style={{ padding: '2rem', textAlign: 'center' }}>
              <p style={{ color: 'var(--muted)', marginBottom: '1rem' }}>
                {compileError || 'PDF not yet compiled.'}
              </p>
              <button className="btn btn-primary" onClick={compilePdf} disabled={compiling}>
                {compiling ? 'Compiling...' : 'Compile PDF'}
              </button>
            </div>
          )
        ) : (
          <pre className="pv-latex-source">{latexSource || 'No LaTeX source available.'}</pre>
        )}
      </div>

      <div className="pv-version-bar">
        <span className="pv-version-label">Paper v{paperVersion}</span>
        <span className="pv-version-sep">·</span>
        <span className="pv-version-label">{lineCount} lines</span>
        {isRewriting && (
          <>
            <span className="pv-version-sep">→</span>
            <span className="pv-version-label" style={{ color: 'var(--primary)', fontWeight: 500 }}>
              v{paperVersion + 1} generating...
            </span>
          </>
        )}
        {!isRewriting && pdfPath && <span className="pv-compiled-badge">Compiled</span>}
      </div>

      {isRewriting && (
        <RewriteOverlay theoryStatus={theoryStatus} writerStatus={writerStatus} />
      )}
    </div>
  );
}
