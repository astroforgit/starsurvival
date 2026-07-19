import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { defineConfig } from "vite";

function directoryRoutes() {
  const redirect = (request, response, next) => {
    const [pathname, query] = (request.url || "").split("?", 2);
    if (!["/intro", "/launch", "/game"].includes(pathname)) {
      next();
      return;
    }
    response.statusCode = 302;
    response.setHeader("Location", `${pathname}/${query ? `?${query}` : ""}`);
    response.end();
  };

  return {
    name: "cosmic-abyss-directory-routes",
    configureServer(server) {
      server.middlewares.use(redirect);
    },
    configurePreviewServer(server) {
      server.middlewares.use(redirect);
    }
  };
}

function atariDownload() {
  return {
    name: "cosmic-abyss-atari-download",
    generateBundle() {
      this.emitFile({
        type: "asset",
        fileName: "cosmic-abyss.xex",
        source: readFileSync(resolve(import.meta.dirname, "atari/cosmic-abyss.xex"))
      });
    }
  };
}

export default defineConfig({
  plugins: [directoryRoutes(), atariDownload()],
  build: {
    rollupOptions: {
      input: {
        home: resolve(import.meta.dirname, "index.html"),
        game: resolve(import.meta.dirname, "game/index.html"),
        intro: resolve(import.meta.dirname, "intro/index.html"),
        launch: resolve(import.meta.dirname, "launch/index.html")
      }
    }
  }
});
