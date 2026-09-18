import type { Metadata } from "next";
import { Gallery } from "./Gallery";

export const metadata: Metadata = { title: "Design system" };

/** Component gallery: every DS component in every state, light and dark side by side. */
export default function DesignPage() {
  return (
    <main id="main" className="min-h-screen bg-background p-6">
      <header className="mb-6 flex flex-col gap-1">
        <h1 className="text-display">Design system</h1>
        <p className="text-body text-text-secondary">
          Components from SPEC 13.1 rendered from design/tokens.json. Left: light theme. Right: dark
          theme.
        </p>
      </header>
      <div className="grid gap-6 xl:grid-cols-2">
        <section
          data-theme="light"
          data-testid="gallery-light"
          className="rounded-sheet border border-border bg-background p-4 text-text"
        >
          <Gallery theme="light" />
        </section>
        <section
          data-theme="dark"
          data-testid="gallery-dark"
          className="rounded-sheet border border-border bg-background p-4 text-text"
        >
          <Gallery theme="dark" />
        </section>
      </div>
    </main>
  );
}
