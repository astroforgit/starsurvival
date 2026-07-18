import { resolve } from "node:path";
import { defineConfig } from "vite";

function introRoute() {
  const redirect = (request, response, next) => {
    const [pathname, query] = (request.url || "").split("?", 2);
    if (pathname !== "/intro") {
      next();
      return;
    }
    response.statusCode = 302;
    response.setHeader("Location", `/intro/${query ? `?${query}` : ""}`);
    response.end();
  };

  return {
    name: "cosmic-abyss-intro-route",
    configureServer(server) {
      server.middlewares.use(redirect);
    },
    configurePreviewServer(server) {
      server.middlewares.use(redirect);
    }
  };
}

export default defineConfig({
  plugins: [introRoute()],
  build: {
    rollupOptions: {
      input: {
        game: resolve(import.meta.dirname, "index.html"),
        intro: resolve(import.meta.dirname, "intro/index.html")
      }
    }
  }
});
