import type { QAMessage } from '@/types';
import { ToolSteps } from './ToolSteps';

interface ChatMessageProps {
  message: QAMessage;
}

function timeAgo(ts?: string): string {
  if (!ts) return '';
  const diff = Date.now() - new Date(ts).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'just now';
  if (mins === 1) return '1 min ago';
  if (mins < 60) return `${mins} min ago`;
  const hrs = Math.floor(mins / 60);
  return hrs === 1 ? '1 hr ago' : `${hrs} hrs ago`;
}

export function ChatMessage({ message }: ChatMessageProps) {
  if (message.role === 'system') {
    return (
      <div className="qa-msg-wrap qa-msg-wrap--system">
        <span className="qa-msg-system">{message.content}</span>
      </div>
    );
  }

  if (message.role === 'user') {
    return (
      <div className="qa-msg-wrap qa-msg-wrap--user">
        <div className="qa-msg-user">{message.content}</div>
        <span className="qa-msg-ts">{timeAgo(message.ts)}</span>
      </div>
    );
  }

  return (
    <div className="qa-msg-wrap qa-msg-wrap--agent">
      {message.tool_steps && <ToolSteps steps={message.tool_steps} />}
      <div className="qa-msg-agent">{message.content}</div>
      <span className="qa-msg-ts">{timeAgo(message.ts)}</span>
    </div>
  );
}
