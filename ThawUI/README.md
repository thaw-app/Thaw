# ThawUI

SwiftUI form and control components for Thaw's settings.

Depends only on SwiftUI, Foundation, CoreGraphics, Combine, and
CompactSlider. It knows nothing about app state, the settings model, or the
menu bar, which is what keeps it usable from more than one app.

`ThawWindow` is not here on purpose. It takes an `AppState` and reads the
app's display name, so it stays in the app target.

## Licensing

GPL-3.0, like the rest of the repository.
