"""Domain plugin registry — maps domain strings to DomainPlugin implementations."""

from __future__ import annotations

from eurekaclaw.domains.base import DomainPlugin

_REGISTRY: dict[str, type[DomainPlugin]] = {}


def register_domain(cls: type[DomainPlugin]) -> type[DomainPlugin]:
    """Decorator to register a DomainPlugin class by its name."""
    _REGISTRY[cls.name] = cls
    return cls


def resolve_domain(domain: str) -> DomainPlugin | None:
    """Return a DomainPlugin instance for the given domain string, or None.

    Matching order:
    1. Exact key match in registry (e.g. "mab")
    2. Keyword scan: plugin declares keywords checked against domain string
    """
    domain_lower = domain.lower()

    # Exact name match
    if domain_lower in _REGISTRY:
        return _REGISTRY[domain_lower]()

    # Keyword scan
    for cls in _REGISTRY.values():
        if any(kw in domain_lower for kw in cls.keywords):
            return cls()

    return None


# Auto-import all domain packages so their @register_domain decorators fire
def _load_all() -> None:
    import importlib

    _DOMAIN_PACKAGES = ["eurekaclaw.domains.mab"]
    for pkg in _DOMAIN_PACKAGES:
        try:
            importlib.import_module(pkg)
        except ImportError:
            pass


_load_all()

__all__ = ["DomainPlugin", "register_domain", "resolve_domain"]
