"""Nested GridStack example with Vue 3 / trame.

Outer grid contains one resizable widget.
Inside that widget there is a nested grid with 3 items in one row:
- items can be rearranged (drag-and-drop)
- items cannot be resized
- items always occupy the full width of the outer widget
"""

from trame.app import get_server
from trame.ui.vuetify3 import SinglePageLayout
from trame.widgets import html

from trame_gridstack.widgets.gridstack import GridStack, GridStackItem

server = get_server()
state = server.state

state.inner_items = [
    {"id": "left", "x": 0, "y": 0, "w": 1, "h": 1, "label": "Left"},
    {"id": "center", "x": 1, "y": 0, "w": 1, "h": 1, "label": "Center"},
    {"id": "right", "x": 2, "y": 0, "w": 1, "h": 1, "label": "Right"},
]


def on_inner_change(items=None, **_):
    if not items:
        return

    by_id = {str(item.get("id")): item for item in items if item and item.get("id")}
    moved_items = []
    for entry in state.inner_items:
        moved = by_id.get(entry["id"], {})
        moved_items.append({**entry, "x": moved.get("x", entry["x"]), "y": moved.get("y", 0)})

    # Keep a strict single-row layout that always fills the parent width.
    reordered = sorted(moved_items, key=lambda item: (item["y"], item["x"]))
    state.inner_items = [
        {**item, "x": index, "y": 0, "w": 1, "h": 1} for index, item in enumerate(reordered)
    ]


with SinglePageLayout(server) as layout:
    layout.title.set_text("GridStack nested grids (Vue 3)")
    layout.toolbar.height = 40

    with layout.content:
        html.Style(
            """
            .outer-widget {
              height: 100%;
              background: #eef2ff;
              border: 1px solid #c7d2fe;
              border-radius: 10px;
              padding: 8px;
              box-sizing: border-box;
            }
            .outer-widget > .grid-stack {
              height: 100%;
              min-height: 100%;
            }
            .inner-card {
              height: 100%;
              display: flex;
              align-items: center;
              justify-content: center;
              border: 1px dashed #6366f1;
              border-radius: 8px;
              background: #e0e7ff;
              font-weight: 600;
              user-select: none;
            }
            """
        )

        with GridStack(
            options={"column": 12, "cellHeight": 80, "margin": 8},
            style="height: calc(100vh - 88px); background: #f8fafc;",
        ):
            with GridStackItem(x=0, y=0, w=12, h=4, id="container"):
                with html.Div(classes="outer-widget"):
                    with GridStack(
                        options={"column": 3, "cellHeight": "auto", "margin": 6},
                        style="height: 100%;",
                        change=(on_inner_change, "[$event]"),
                    ):
                        with html.Template(v_for="item in inner_items", key="item.id"):
                            with GridStackItem(
                                x=("item.x",),
                                y=("item.y",),
                                w=("item.w",),
                                h=("item.h",),
                                id=("item.id",),
                                minW=1,
                                maxW=1,
                                minH=1,
                                maxH=1,
                                noResize=True,
                            ):
                                html.Div("{{ item.label }}", classes="inner-card")


if __name__ == "__main__":
    server.start()
