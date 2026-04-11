"""Simple layout example inspired by trame-grid-layout/simple_layout.py."""

from trame.app import get_server
from trame.ui.vuetify3 import SinglePageLayout
from trame.widgets import html
from trame_gridstack.widgets.gridstack import GridStack, GridStackItem

server = get_server()
state = server.state

state.layout = [
    {"x": 0, "y": 0, "w": 2, "h": 2, "i": "0"},
    {"x": 2, "y": 0, "w": 2, "h": 4, "i": "1"},
    {"x": 4, "y": 0, "w": 2, "h": 5, "i": "2"},
    {"x": 6, "y": 0, "w": 2, "h": 3, "i": "3"},
    {"x": 8, "y": 0, "w": 2, "h": 3, "i": "4"},
    {"x": 10, "y": 0, "w": 2, "h": 3, "i": "5"},
    {"x": 0, "y": 5, "w": 2, "h": 5, "i": "6"},
    {"x": 2, "y": 5, "w": 2, "h": 5, "i": "7"},
    {"x": 4, "y": 5, "w": 2, "h": 5, "i": "8"},
    {"x": 6, "y": 3, "w": 2, "h": 4, "i": "9"},
    {"x": 8, "y": 4, "w": 2, "h": 4, "i": "10"},
    {"x": 10, "y": 4, "w": 2, "h": 4, "i": "11"},
    {"x": 0, "y": 10, "w": 2, "h": 5, "i": "12"},
    {"x": 2, "y": 10, "w": 2, "h": 5, "i": "13"},
    {"x": 4, "y": 8, "w": 2, "h": 4, "i": "14"},
    {"x": 6, "y": 8, "w": 2, "h": 4, "i": "15"},
    {"x": 8, "y": 10, "w": 2, "h": 5, "i": "16"},
    {"x": 10, "y": 4, "w": 2, "h": 2, "i": "17"},
    {"x": 0, "y": 9, "w": 2, "h": 3, "i": "18"},
    {"x": 2, "y": 6, "w": 2, "h": 2, "i": "19"},
]


def on_change(items=None, **_):
    if items is None:
        return

    by_id = {str(item.get("id")): item for item in items if item}
    state.layout = [
        {
            **entry,
            "x": by_id.get(entry["i"], {}).get("x", entry["x"]),
            "y": by_id.get(entry["i"], {}).get("y", entry["y"]),
            "w": by_id.get(entry["i"], {}).get("w", entry["w"]),
            "h": by_id.get(entry["i"], {}).get("h", entry["h"]),
        }
        for entry in state.layout
    ]


with SinglePageLayout(server) as layout:
    layout.title.set_text("GridStack simple layout")
    layout.toolbar.height = 32

    with layout.content:
        with GridStack(
            options={"column": 12, "cellHeight": 20, "margin": 5},
            style="height: calc(100vh - 64px);",
            change=(on_change, "[$event]"),
        ):
            with html.Template(v_for="item in layout", key="item.i"):
                with GridStackItem(
                    x=("item.x",),
                    y=("item.y",),
                    w=("item.w",),
                    h=("item.h",),
                    id=("item.i",),
                ):
                    html.Div(
                        "{{ item.i }}",
                        classes="pa-4",
                        style="border: solid 1px #333; background: rgba(128, 128, 128, 0.5); touch-action: none; height: 100%;",
                    )


if __name__ == "__main__":
    server.start()