(function (global) {
  const GRIDSTACK_JS = "https://cdn.jsdelivr.net/npm/gridstack@10.3.1/dist/gridstack-all.js";
  const GRIDSTACK_CSS = "https://cdn.jsdelivr.net/npm/gridstack@10.3.1/dist/gridstack.min.css";

  function loadScript(src) {
    return new Promise((resolve, reject) => {
      const existing = document.querySelector(`script[src=\"${src}\"]`);
      if (existing) {
        existing.addEventListener("load", () => resolve(), { once: true });
        if (existing.dataset.loaded === "1") {
          resolve();
        }
        return;
      }
      const el = document.createElement("script");
      el.src = src;
      el.async = true;
      el.onload = () => {
        el.dataset.loaded = "1";
        resolve();
      };
      el.onerror = reject;
      document.head.appendChild(el);
    });
  }

  function loadCss(href) {
    const existing = document.querySelector(`link[href=\"${href}\"]`);
    if (existing) {
      return;
    }
    const el = document.createElement("link");
    el.rel = "stylesheet";
    el.href = href;
    document.head.appendChild(el);
  }

  const GridStackComponent = {
    name: "TrameGridStack",
    props: {
      options: {
        type: Object,
        default: () => ({}),
      },
      animate: {
        type: Boolean,
        default: true,
      },
    },
    emits: ["change", "added", "removed"],
    template: `<div class=\"grid-stack\" ref=\"root\"><slot /></div>`,
    data() {
      return {
        grid: null,
      };
    },
    async mounted() {
      loadCss(GRIDSTACK_CSS);
      await loadScript(GRIDSTACK_JS);
      await this.$nextTick();

      const config = { ...this.options, animate: this.animate };
      this.grid = global.GridStack.init(config, this.$refs.root);

      const toPlainItems = (items) => {
        const list = Array.isArray(items) ? items : [];
        const keys = [
          "id", "x", "y", "w", "h", "minW", "minH", "maxW", "maxH", "locked", "noMove", "noResize",
        ];

        return list.map((i) => {
          if (!i) return null;

          const src = typeof i.toJSON === "function" ? i.toJSON() : i;
          const out = {};
          keys.forEach((k) => {
            if (src[k] !== undefined) {
              out[k] = src[k];
            }
          });
          return out;
        });
      };

      this.grid.on("change", (_event, items) => {
        this.$emit("change", toPlainItems(items));
      });
      this.grid.on("added", (_event, items) => {
        this.$emit("added", toPlainItems(items));
      });
      this.grid.on("removed", (_event, items) => {
        this.$emit("removed", toPlainItems(items));
      });
    },
    beforeUnmount() {
      if (this.grid) {
        this.grid.destroy(false);
        this.grid = null;
      }
    },
  };

  const GridStackItemComponent = {
    name: "TrameGridItem",
    props: {
      x: { type: Number, default: 0 },
      y: { type: Number, default: 0 },
      w: { type: Number, default: 1 },
      h: { type: Number, default: 1 },
      minW: { type: Number, default: undefined },
      minH: { type: Number, default: undefined },
      maxW: { type: Number, default: undefined },
      maxH: { type: Number, default: undefined },
      id: { type: [String, Number], default: undefined },
      locked: { type: Boolean, default: false },
      noResize: { type: Boolean, default: false },
      noMove: { type: Boolean, default: false },
    },
    computed: {
      attrs() {
        return {
          "gs-x": this.x,
          "gs-y": this.y,
          "gs-w": this.w,
          "gs-h": this.h,
          "gs-min-w": this.minW,
          "gs-min-h": this.minH,
          "gs-max-w": this.maxW,
          "gs-max-h": this.maxH,
          "gs-id": this.id,
          "gs-locked": this.locked,
          "gs-no-resize": this.noResize,
          "gs-no-move": this.noMove,
        };
      },
    },
    template: `
      <div class=\"grid-stack-item\" v-bind=\"attrs\">
        <div class=\"grid-stack-item-content\"><slot /></div>
      </div>
    `,
  };

  const TrameGridStack = {
    install(app) {
      app.component("trame-grid-stack", GridStackComponent);
      app.component("trame-grid-item", GridStackItemComponent);
    },
  };

  if (global.Vue && global.Vue.createApp) {
    global.TrameGridStack = TrameGridStack;
  }
})(window);
