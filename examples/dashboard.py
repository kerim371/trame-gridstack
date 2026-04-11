"""Dashboard-like trame-gridstack example with dynamic updates."""

from trame.app import get_server
from trame.ui.html import DivLayout
from trame.widgets import html
from trame_gridstack.widgets.gridstack import GridStack, GridStackItem

server = get_server()
state = server.state

state.widgets = [
    {"id": "sales", "title": "Sales", "x": 0, "y": 0, "w": 6, "h": 2, "color": "#e0f2fe"},
    {"id": "ops", "title": "Ops", "x": 6, "y": 0, "w": 6, "h": 2, "color": "#fef3c7"},
    {"id": "alerts", "title": "Alerts", "x": 0, "y": 2, "w": 12, "h": 2, "color": "#fee2e2"},
]


def add_widget():
    index = len(state.widgets) + 1
    state.widgets = [
        *state.widgets,
        {
            "id": f"extra-{index}",
            "title": f"Extra #{index}",
            "x": 0,
            "y": 99,
            "w": 4,
            "h": 1,
            "color": "#dcfce7",
        },
    ]


with DivLayout(server) as layout:
    layout.title.set_text("trame-gridstack: dashboard")

    html.Button("Add widget", click=add_widget, style="margin-bottom: 8px;")

    with GridStack(options={"column": 12, "cellHeight": 70, "margin": 8}, style="height: 520px;"):
        with html.Template(v_for="w in widgets", key="w.id"):
            with GridStackItem(x=("w.x",), y=("w.y",), w=("w.w",), h=("w.h",), id=("w.id",)):
                with html.Div(style=("`background:${w.color};height:100%;padding:8px;`",)):
                    html.H4("{{ w.title }}", style="margin: 0;")
                    html.Div("id: {{ w.id }}")


if __name__ == "__main__":
    server.start()
