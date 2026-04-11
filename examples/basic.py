"""Basic trame-gridstack example."""

from trame.app import get_server
from trame.ui.html import DivLayout
from trame.widgets import html
from trame_gridstack.widgets import GridStack, GridStackItem

server = get_server()
state = server.state

state.layout_events = []


def on_layout_change(items):
    state.layout_events = items


with DivLayout(server) as layout:
    layout.title.set_text("trame-gridstack: basic")

    with GridStack(
        options={"column": 12, "cellHeight": 80, "margin": 8},
        style="height: 420px; background: #f5f5f5;",
        change=on_layout_change,
    ):
        with GridStackItem(x=0, y=0, w=4, h=2, id="a"):
            html.Div("A", classes="pa-2", style="background: #dbeafe; height: 100%;")

        with GridStackItem(x=4, y=0, w=4, h=3, id="b"):
            html.Div("B", classes="pa-2", style="background: #dcfce7; height: 100%;")

        with GridStackItem(x=8, y=0, w=4, h=1, id="c"):
            html.Div("C", classes="pa-2", style="background: #fee2e2; height: 100%;")

    html.Pre("{{ layout_events }}", style="margin-top: 16px; font-size: 12px;")


if __name__ == "__main__":
    server.start()
