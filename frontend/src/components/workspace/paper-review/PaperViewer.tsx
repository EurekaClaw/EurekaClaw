import { useState, useEffect, useCallback, useRef } from 'react';
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
  // Whether a PDF is available to display in the iframe.
  const [pdfAvailable, setPdfAvailable] = useState(false);
  const [pdfCacheBuster, setPdfCacheBuster] = useState(0);
  // Using a ref (not state) avoids re-triggering the compile effect just
  // because we marked the attempt — which would cancel our own in-flight
  // request and strand `compiling` at true forever.
  const attemptedRef = useRef(false);
  const [prevVersion, setPrevVersion] = useState(paperVersion);

  // Note: session switches are handled by key={run.run_id} on the
  // parent — React remounts a fresh instance, so no manual reset needed.

  // Reset PDF state when paper version changes (after rewrite).
  if (paperVersion !== prevVersion) {
    setPrevVersion(paperVersion);
    setPdfAvailable(false);
    attemptedRef.current = false;
    setCompileError('');
  }

  // Clear when a rewrite starts so the overlay replaces the iframe.
  const [wasRewriting, setWasRewriting] = useState(isRewriting);
  if (isRewriting && !wasRewriting) {
    setPdfAvailable(false);
    attemptedRef.current = false;
    setCompileError('');
  }
  if (isRewriting !== wasRewriting) {
    setWasRewriting(isRewriting);
  }

  // On mount, auto-compile the PDF. The compile-pdf endpoint is
  // idempotent — if the PDF already exists and LaTeX hasn't changed,
  // it returns immediately. No separate probe needed (probing the
  // artifact endpoint has side effects that can delete valid PDFs).
  // The attemptedRef guard prevents double-compile (including React
  // StrictMode's double-invoke); no in-flight cancellation flag is
  // needed because the parent remounts on session change via key prop.
  const pdfUrl = `/api/runs/${run.run_id}/artifacts/paper.pdf`;
  useEffect(() => {
    if (pdfAvailable || isRewriting || attemptedRef.current) return;
    attemptedRef.current = true;
    setCompiling(true);
    void (async () => {
      try {
        const res = await apiPost<CompileResponse>(
          `/api/runs/${run.run_id}/compile-pdf`, {}
        );
        if (res.ok) {
          setPdfAvailable(true);
          setPdfCacheBuster(Date.now());
        } else {
          setCompileError(res.error || 'Compilation failed');
        }
      } catch (e) {
        setCompileError(String(e));
      } finally {
        setCompiling(false);
      }
    })();
  }, [pdfAvailable, isRewriting, run.run_id]);

  // Source LaTeX from writer task outputs (available during gate) or fallback to run.result
  const writerTask = run.pipeline?.find((t) => t.name === 'writer');
  const latexSource = (writerTask?.outputs?.latex_paper as string) || run.result?.latex_paper || '';
  const lineCount = latexSource ? latexSource.split('\n').length : 0;

  const compilePdf = useCallback(async () => {
    setCompiling(true);
    setCompileError('');
    try {
      const res = await apiPost<CompileResponse>(`/api/runs/${run.run_id}/compile-pdf`, {});
      if (res.ok) {
        setPdfAvailable(true);
        setPdfCacheBuster(Date.now());
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
            href={pdfUrl}
            target="_blank"
            rel="noreferrer"
            className="pv-download-btn"
          >
            ⬇ .pdf
          </a>
        </div>
      </div>

      <div className={`pv-content${activeTab === 'latex' ? ' pv-content--latex' : ''}`}>
        {activeTab === 'pdf' ? (
          pdfAvailable ? (
            <iframe
              className="pv-pdf-frame"
              src={`${pdfUrl}?v=${pdfCacheBuster}`}
              title="Paper PDF"
            />
          ) : (
            <div className="paper-empty-state">
              {compiling ? (
                <>
                  <div className="paper-progress-dots"><span /><span /><span /></div>
                  <p>Compiling PDF...</p>
                </>
              ) : compileError ? (
                <>
                  <p style={{ color: 'var(--warn)', marginBottom: '1rem' }}>{compileError}</p>
                  <button className="btn btn-primary" onClick={compilePdf}>
                    Retry
                  </button>
                </>
              ) : (
                <>
                  <div className="paper-progress-dots"><span /><span /><span /></div>
                  <p>Preparing PDF...</p>
                </>
              )}
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
        {!isRewriting && pdfAvailable && <span className="pv-compiled-badge">Compiled</span>}
      </div>

      {isRewriting && (
        <RewriteOverlay theoryStatus={theoryStatus} writerStatus={writerStatus} />
      )}
    </div>
  );
}
