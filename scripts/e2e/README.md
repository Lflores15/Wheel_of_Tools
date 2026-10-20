Real-drag test helpers (need Accessibility permission for your terminal).
- `evt.swift`: posts mouse/modifier events (`swiftc -O evt.swift -o evt`)
- `ax.swift`: finds a Finder item's on-screen position via Accessibility (`ax photo.jpg`)
- `steps.sh`: `steps x0 y0 x1 y1 n [shift|ctrl]` emits interpolated drag events

Flow that passed: Finder window in list view on a folder with photo.jpg → mouse down on the name →
drag 15 steps → `evt shift down` → move to the WEBP segment (center + 126,+52) → `evt up` → photo.webp appears.
Control + Crop segment (center + 118,-68) opens the editor window.
