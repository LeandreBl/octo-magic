import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Dev: `docker compose up` (or node backend/server.js) on :8080 serves the API,
// the coop lobby and the game's web export under /game.
const server = process.env.OCTO_SERVER ?? "http://localhost:8080";

export default defineConfig({
  plugins: [react()],
  server: {
    fs: { allow: [".."] }, // fonts and icons from ../assets
    proxy: { "/api": server, "/game": server, "/terms": server, "/privacy": server },
  },
});
