"""GridStack title-drag example (port of official title_drag.html) using Vuetify 3."""

from trame.app import get_server
from trame.ui.vuetify3 import SinglePageLayout
from trame.widgets import html, vuetify3
from trame_gridstack.widgets.gridstack import GridStack, GridStackItem

server = get_server()

with SinglePageLayout(server) as layout:
    layout.title.set_text("Title area drag")
    layout.toolbar.height = 48

    with layout.content:
        with html.Div(classes="pa-4"):
            html.H2("Title area drag", classes="mb-4")

            with GridStack(
                options={
                    "column": 12,
                    "cellHeight": 80,
                    "margin": 8,
                    "handle": ".card-header",  # drag by header only
                },
                style="min-height: 340px; background: #f7f7f7;",
            ):
                with GridStackItem(x=0, y=0, w=3, h=3, id="title-drag-card"):
                    with vuetify3.VCard(classes="h-100"):
                        vuetify3.VCardTitle(
                            "- Drag here -",
                            classes="card-header text-center",
                            style="cursor: move; user-select: none;",
                        )
                        with vuetify3.VCardText(classes="d-flex align-center justify-center", style="height: calc(100% - 64px);"):
                            html.Div("the rest of the panel content doesn't drag")


if __name__ == "__main__":
    server.start()
