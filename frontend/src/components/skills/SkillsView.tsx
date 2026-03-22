import { useState } from 'react';
import { ClawHubPanel } from './ClawHubPanel';
import { SkillLibrary } from './SkillLibrary';
import { SelectedSkillsPanel } from './SelectedSkillsPanel';

export function SkillsView() {
  const [clawStatus, setClawStatus] = useState('');
  const [clawStatusError, setClawStatusError] = useState(false);

  const handleStatus = (msg: string, isError = false) => {
    setClawStatus(msg);
    setClawStatusError(isError);
  };

  return (
    <div className="skills-shell">
      <ClawHubPanel status={clawStatus} statusError={clawStatusError} onStatus={handleStatus} />
      <SkillLibrary onClawHubStatus={handleStatus} />
      <SelectedSkillsPanel />
    </div>
  );
}
