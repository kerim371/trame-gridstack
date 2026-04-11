"""Python widget wrappers for trame-gridstack components."""

from trame_client.widgets.core import AbstractElement

from trame_gridstack import module


class GridStack(AbstractElement):
    """Main GridStack container."""

    def __init__(self, children=None, **kwargs):
        super().__init__("trame-grid-stack", children, **kwargs)
        self.server.enable_module(module)


class GridStackItem(AbstractElement):
    """Single GridStack item."""

    def __init__(self, children=None, **kwargs):
        super().__init__("trame-grid-item", children, **kwargs)
        self.server.enable_module(module)
