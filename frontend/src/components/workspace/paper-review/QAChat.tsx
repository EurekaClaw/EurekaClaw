import { useState, useRef, useEffect } from 'react';
import { apiPost } from '@/api/client';
import { ChatMessage } from './ChatMessage';
import type { SessionRun, QAMessage } from '@/types';

interface QAChatProps {
  run: SessionRun;
  messages: QAMessage[];
  setMessages: React.Dispatch<React.SetStateAction<QAMessage[]>>;
  isRewriting: boolean;
  isHistorical: boolean;
  onAccept: () => void;
  onRewrite: (prompt: string) => void;
}

interface AskResponse {
  answer: string;
  tool_steps?: { tool: string; input: string; status: string }[];
  error?: string;
}

export function QAChat({ run, messages, setMessages, isRewriting, isHistorical, onAccept, onRewrite }: QAChatProps) {
  const [input, setInput] = useState('');
  const [sending, setSending] = useState(false);
  const [rewriteMode, setRewriteMode] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  async function handleSend() {
    const text = input.trim();
    if (!text || sending) return;

    if (rewriteMode) {
      setRewriteMode(false);
      setInput('');
      onRewrite(text);
      return;
    }

    const userMsg: QAMessage = {
      role: 'user',
      content: text,
      ts: new Date().toISOString(),
    };
    setMessages((prev) => [...prev, userMsg]);
    setInput('');
    setSending(true);

    try {
      // Fold system markers (rewrite requests) into user turns instead
      // of dropping them. Anthropic's messages API rejects role:"system"
      // in the message list, but the rewrite-request text is real
      // context the agent needs to answer follow-ups like "did you
      // address my earlier feedback?" — so we preserve it as a user
      // turn rather than filtering it out.
      const history = messages.flatMap((m) => {
        if (m.role === 'user' || m.role === 'assistant') {
          return [{ role: m.role, content: m.content }];
        }
        if (m.role === 'system') {
          return [{ role: 'user' as const, content: m.content }];
        }
        return [];
      });
      const res = await apiPost<AskResponse>(`/api/runs/${run.run_id}/paper-qa/ask`, {
        question: text,
        history,
      });

      const agentMsg: QAMessage = {
        role: 'assistant',
        content: res.answer || res.error || 'No response',
        ts: new Date().toISOString(),
        tool_steps: res.tool_steps?.map((s) => ({
          tool: s.tool,
          input: s.input,
          status: s.status as 'done' | 'running' | 'pending' | 'failed',
        })),
      };
      setMessages((prev) => [...prev, agentMsg]);
    } catch (e) {
      const errorMsg: QAMessage = {
        role: 'assistant',
        content: `Error: ${e instanceof Error ? e.message : String(e)}`,
        ts: new Date().toISOString(),
      };
      setMessages((prev) => [...prev, errorMsg]);
    } finally {
      setSending(false);
    }
  }

  function handleKeyDown(e: React.KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  }

  function handleRewriteClick() {
    setRewriteMode(true);
    setInput('');
  }

  const placeholder = isRewriting
    ? 'Waiting for rewrite to complete...'
    : rewriteMode
    ? 'Describe what to fix...'
    : 'Ask about the paper...';

  return (
    <div className="qa-chat">
      <div className="qa-chat-header">
        <span className="qa-chat-title">Paper Q&A</span>
        <span className={`qa-chat-badge${isRewriting ? ' qa-chat-badge--rewriting' : ''}`}>
          {isRewriting ? 'Rewriting...' : `${messages.length} messages`}
        </span>
      </div>

      <div className="qa-messages">
        {messages.length === 0 && !sending && (
          <div className="qa-empty-state">
            Ask questions about the paper, request changes, or start a rewrite.
          </div>
        )}
        {messages.map((msg, i) => (
          <ChatMessage key={i} message={msg} />
        ))}
        {sending && (
          <div className="qa-msg-wrap qa-msg-wrap--agent">
            <div className="tool-steps">
              <div className="tool-step">
                <span className="tool-step-dot tool-step-dot--running" />
                <span>Thinking...</span>
              </div>
            </div>
          </div>
        )}
        <div ref={messagesEndRef} />
      </div>

      <div className={`qa-input-area${isRewriting ? ' qa-input-area--disabled' : ''}`}>
        <div className="qa-input-row">
          <textarea
            className="qa-input-field"
            placeholder={placeholder}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            rows={1}
            disabled={isRewriting || sending}
          />
          <button
            className="qa-send-btn"
            onClick={handleSend}
            disabled={isRewriting || sending || !input.trim()}
          >
            {rewriteMode ? 'Rewrite' : 'Send'}
          </button>
        </div>
        {!rewriteMode && (
          <div className="qa-action-row">
            {!isHistorical && (
              <button className="qa-accept-btn" onClick={onAccept} disabled={isRewriting || sending}>
                ✓ Accept Paper
              </button>
            )}
            <button className="qa-rewrite-btn" onClick={handleRewriteClick} disabled={isRewriting || sending}>
              ↻ Revise Paper
            </button>
          </div>
        )}
        {rewriteMode && (
          <div className="qa-action-row">
            <button className="qa-accept-btn" onClick={() => setRewriteMode(false)}>
              Cancel
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
