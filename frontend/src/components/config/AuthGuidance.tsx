import { useState } from 'react';

interface AuthGuidanceProps {
  backend: string;
  authMode: string;
  ccproxyPort: string;
}

export function AuthGuidance({ backend, authMode, ccproxyPort }: AuthGuidanceProps) {
  const [isOpen, setIsOpen] = useState(false);

  let title = '';
  let steps: { heading: string; items: string[] }[] = [];
  let terminalCmds = '';

  if (backend === 'anthropic' && authMode === 'oauth') {
    title = 'OAuth setup guide';
    steps = [
      {
        heading: 'Configure',
        items: [
          'Set backend to Anthropic',
          'Set auth mode to OAuth',
          `Choose ccproxy port (e.g. ${ccproxyPort})`,
          'Leave API key empty',
        ],
      },
      {
        heading: 'Requirements',
        items: [
          'Click "Install OAuth dependencies" if ccproxy is not installed',
          'Click "Login with Anthropic" to authorize',
          'Click "Save & test" to verify the connection',
        ],
      },
    ];
    terminalCmds = `# Manual setup (if the buttons above don't work):\npip install -e '.[oauth]'\nccproxy auth login claude_api\nccproxy auth status claude_api`;
  } else if (backend === 'anthropic') {
    title = 'API key setup guide';
    steps = [
      {
        heading: 'Steps',
        items: [
          'Get an API key from console.anthropic.com',
          'Paste it in the field above',
          'Click "Save & test"',
        ],
      },
      {
        heading: 'Troubleshooting',
        items: [
          'Check for extra whitespace when pasting',
          'Ensure key is not expired',
          'Verify model access is enabled',
        ],
      },
    ];
  } else {
    title = 'OpenAI-compatible setup guide';
    steps = [
      {
        heading: 'Steps',
        items: [
          'Enter the base URL (include /v1 if needed)',
          'Enter your API key',
          'Set the model name',
          'Click "Save & test"',
        ],
      },
      {
        heading: 'Troubleshooting',
        items: [
          'Missing /v1 suffix in base URL',
          'Model not supported by endpoint',
          'OpenAI Python package not installed',
        ],
      },
    ];
  }

  return (
    <div className={`settings-guidance${isOpen ? ' is-open' : ''}`}>
      <button
        className="settings-guidance-toggle"
        type="button"
        onClick={() => setIsOpen(!isOpen)}
      >
        <span className="settings-guidance-icon">💡</span>
        <span className="settings-guidance-label">{title}</span>
        <span className="settings-guidance-arrow">{isOpen ? '▾' : '▸'}</span>
      </button>
      {isOpen && (
        <div className="settings-guidance-body">
          <div className="settings-guidance-grid">
            {steps.map((s, i) => (
              <div key={i} className="settings-guidance-card">
                <p className="settings-guidance-card-heading">{s.heading}</p>
                <ol className="settings-guidance-list">
                  {s.items.map((item, j) => (
                    <li key={j}>{item}</li>
                  ))}
                </ol>
              </div>
            ))}
          </div>
          {terminalCmds && (
            <div className="settings-guidance-terminal">
              <p className="settings-guidance-card-heading">Terminal commands</p>
              <pre>{terminalCmds}</pre>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
