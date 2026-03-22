import { useState } from 'react';

interface AuthGuidanceProps {
  backend: string;
  authMode: string;
  ccproxyPort: string;
}

export function AuthGuidance({ backend, authMode, ccproxyPort }: AuthGuidanceProps) {
  const [isOpen, setIsOpen] = useState(false);

  let title = 'Connection guidance';
  let content: React.ReactNode = null;

  if (backend === 'anthropic' && authMode === 'oauth') {
    title = 'Anthropic OAuth guidance';
    content = (
      <>
        <div>
          <p className="eyebrow">OAuth Guidance</p>
          <h4>Anthropic + OAuth requires local ccproxy setup</h4>
        </div>
        <p>This mode does not work from frontend settings alone. EurekaClaw must be able to find a working <code>ccproxy</code> binary and a valid OAuth login for <code>claude_api</code>.</p>
        <div className="hint-grid">
          <div className="hint-card">
            <h5>What to configure</h5>
            <ul>
              <li>Set <code>LLM_BACKEND=anthropic</code></li>
              <li>Set <code>ANTHROPIC_AUTH_MODE=oauth</code></li>
              <li>Choose a <code>CCPROXY_PORT</code> such as <code>{ccproxyPort}</code></li>
              <li>Leave <code>ANTHROPIC_API_KEY</code> empty</li>
            </ul>
          </div>
          <div className="hint-card">
            <h5>What must exist locally</h5>
            <ul>
              <li><code>ccproxy</code> installed and on PATH</li>
              <li>OAuth login completed with Claude provider</li>
              <li>The selected port available locally</li>
            </ul>
          </div>
        </div>
        <div>
          <h5>Recommended terminal checks</h5>
          <pre>{`which ccproxy\nccproxy auth login claude_api\nccproxy auth status claude_api`}</pre>
        </div>
        <p>If <code>Test connection</code> still fails, the most likely causes are: missing <code>ccproxy</code>, no OAuth login, wrong port, or missing project OAuth dependencies.</p>
      </>
    );
  } else if (backend === 'anthropic') {
    title = 'Anthropic API key guidance';
    content = (
      <>
        <div>
          <p className="eyebrow">API Key Guidance</p>
          <h4>Anthropic API key is the simplest way to get running</h4>
        </div>
        <p>Use this path if you want the fastest setup. Fill in <code>ANTHROPIC_API_KEY</code>, keep <code>ANTHROPIC_AUTH_MODE=api_key</code>, then click <code>Test connection</code>.</p>
        <div className="hint-grid">
          <div className="hint-card">
            <h5>Required</h5>
            <ul>
              <li><code>LLM_BACKEND=anthropic</code></li>
              <li><code>ANTHROPIC_AUTH_MODE=api_key</code></li>
              <li>A valid <code>ANTHROPIC_API_KEY</code></li>
            </ul>
          </div>
          <div className="hint-card">
            <h5>Common issues</h5>
            <ul>
              <li>Empty or expired key</li>
              <li>Extra whitespace when pasting</li>
              <li>Model access not enabled for the selected model</li>
            </ul>
          </div>
        </div>
      </>
    );
  } else {
    title = 'OpenAI-compatible guidance';
    content = (
      <>
        <div>
          <p className="eyebrow">OpenAI-Compatible Guidance</p>
          <h4>Custom endpoint mode needs base URL, API key, and model</h4>
        </div>
        <p>Use this mode for OpenRouter, vLLM, SGLang, LM Studio, or another OpenAI-compatible endpoint.</p>
        <div className="hint-grid">
          <div className="hint-card">
            <h5>Required</h5>
            <ul>
              <li><code>OPENAI_COMPAT_BASE_URL</code></li>
              <li><code>OPENAI_COMPAT_API_KEY</code></li>
              <li><code>OPENAI_COMPAT_MODEL</code></li>
            </ul>
          </div>
          <div className="hint-card">
            <h5>Common issues</h5>
            <ul>
              <li>Missing <code>/v1</code> suffix in base URL</li>
              <li>Model name not supported by the endpoint</li>
              <li>OpenAI Python package not installed in the backend environment</li>
            </ul>
          </div>
        </div>
      </>
    );
  }

  return (
    <div className={`full-width auth-guidance-shell${isOpen ? ' is-open' : ''}`} id="auth-guidance-shell">
      <button
        className="auth-guidance-toggle"
        type="button"
        id="auth-guidance-toggle"
        aria-expanded={isOpen}
        onClick={() => setIsOpen(!isOpen)}
        onMouseEnter={() => setIsOpen(true)}
        onMouseLeave={() => setIsOpen(false)}
      >
        <span className="auth-guidance-toggle-label">{title}</span>
        <span className="auth-guidance-toggle-meta" id="auth-guidance-toggle-meta">
          {isOpen ? 'Tap to hide' : 'Tap to view'}
        </span>
      </button>
      {isOpen && (
        <div className="auth-guidance" id="auth-guidance">
          {content}
        </div>
      )}
    </div>
  );
}
