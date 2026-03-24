from rich.console import Console

# Singleton instance with record=True to capture all terminal output
# including all stdout, stderr, and Python logging (via RichHandler).
console = Console(record=True)