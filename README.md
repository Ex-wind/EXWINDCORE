# EXWINDCORE

The shared core framework for the EXWIND addon suite.

## Project Relationships and Localization

### Runtime Dependencies

- [EXBOSS](https://github.com/Ex-wind/EXBOSS) requires `ExwindCore`. Install the `ExwindCore` addon directory from this repository alongside EXBOSS.
- [ExwindTools](https://github.com/Ex-wind/ExwindTools) requires `ExwindCore`. Install the `ExwindCore` addon directory from this repository alongside ExwindTools.
- EXBOSS and ExwindTools both use this shared core; neither addon is a runtime dependency of the other.

### Localization

- Shared locale entry point: [ExwindCore/Locale/Init.lua](ExwindCore/Locale/Init.lua)
- All shared locale files: [ExwindCore/Locale](ExwindCore/Locale)
- EXBOSS-specific encounter text and localization are maintained in [the EXBOSS locale directory](https://github.com/Ex-wind/EXBOSS/tree/main/EXBOSS-Locale).
