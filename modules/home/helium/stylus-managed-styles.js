
// Appended to Stylus's service worker by ./default.nix. It imports the
// userstyles Nix generates into managed-styles.json, the same file the manual
// Import button would take, so a rebuild reaches the browser without any
// clicking. Stylus exposes its API on the worker global and resolves `_busy`
// once its database is loaded.
//
// Styles are matched by name, as the Import button does. A style is rewritten
// only when its source or variable values differ, because the worker restarts
// whenever it goes idle and an unconditional import would churn the database.
// Enabling or disabling a managed style in the Stylus UI is left alone.
(async () => {
  try {
    if (self._busy) await self._busy;
    const response = await fetch(chrome.runtime.getURL("managed-styles.json"));
    const items = await response.json();
    const existing = new Map(
      self.API.styles.getAll().map((style) => [style.name.trim(), style]),
    );
    const varValues = (style) =>
      JSON.stringify(
        Object.entries(style.usercssData?.vars ?? {}).map(([name, v]) => [
          name,
          v.value ?? v.default,
        ]),
      );
    const changed = [];
    for (const item of items) {
      if (item.settings) {
        self.API.prefs.set(item.settings);
        continue;
      }
      const old = existing.get(item.name.trim());
      if (old) {
        if (
          old.sourceCode === item.sourceCode &&
          varValues(old) === varValues(item)
        ) {
          continue;
        }
        item.id = old.id;
        item.enabled = old.enabled;
      }
      changed.push(item);
    }
    if (changed.length) {
      const results = await self.API.styles.importMany(changed);
      for (const { err } of results) {
        if (err) console.error("Stylus managed styles:", err);
      }
    }
  } catch (error) {
    console.error("Stylus managed styles:", error);
  }
})();
