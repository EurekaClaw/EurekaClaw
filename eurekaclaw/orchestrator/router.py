"""TaskRouter — maps task agent_role to the correct agent instance."""

from __future__ import annotations

from eurekaclaw.agents.base import BaseAgent
from eurekaclaw.types.agents import AgentRole
from eurekaclaw.types.tasks import Task


class TaskRouter:
    """Resolves a Task to the appropriate BaseAgent."""

    def __init__(self, agents: dict[AgentRole, BaseAgent]) -> None:
        self._agents = agents

    def resolve(self, task: Task) -> BaseAgent:
        role = AgentRole(task.agent_role)
        agent = self._agents.get(role)
        if not agent:
            raise ValueError(f"No agent registered for role: {role}")
        return agent
