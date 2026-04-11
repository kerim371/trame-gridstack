"""Module definition to serve frontend assets."""

from pathlib import Path

serve_path = Path(__file__).parent / "serve"

serve = {
    "trame-gridstack": serve_path,
}

scripts = [
    "trame-gridstack/trame-gridstack.umd.js",
]

vue_use = [
    "TrameGridStack",
]


def setup(server):
    """Enable trame-gridstack assets on the provided server."""
    from trame_gridstack import module

    server.enable_module(module)
