# Accessibility

Task Manager aims to be usable with VoiceOver, the keyboard alone, and the macOS accessibility display settings.

**VoiceOver**
- Every button, toggle, picker and field has a label. Icon-only buttons are named (Details, End Task, Columns, Collapse sidebar, …).
- Process rows are read as one sentence: name, then each visible column with its unit ("Safari, CPU 0.1 percent, Memory 56 MB, Disk 0 bytes per second, PID 1290"), with *Show details* and *End task* as actions.
- Sidebar pages announce their live value ("CPU, 34%"). Graphs are summarised in words (now and highest over the last 60 seconds) instead of being read point by point; decorative thumbnails are hidden.
- Page titles and section titles are headings, so the headings rotor works. Status rows say "OK" or "Needs attention".

**Keyboard**
- ⌘1–⌘7 switch pages, ⌘, opens Settings, ⌘I shows details, ⌘⌫ ends the selected task (after the usual confirmation).
- In the process list: ↑ ↓ move the selection, Return shows details, Esc closes them. Esc also clears the search.
- Every control is reachable with Full Keyboard Access.

**Display**
- **Text size** (Settings → Appearance): Small, Standard, Large and Extra large. Fonts, row heights and column widths scale together.
- **Reduce Motion** turns off the gauge and sidebar animations. **Increase Contrast** strengthens card borders.
- Accent colours are checked against the WCAG contrast ratio (4.5:1 for text and for fills that carry white text, 3:1 for chart lines) by `--selftest`, in Light, Dark and OLED Black. Secondary text uses the system secondary colour rather than a fainter tint.
- Nothing is conveyed by colour alone: the second series on Disk and Network is dashed, and values are always printed as text.

**Known limits**
- System controls (pop-up menus, switches, buttons) keep their standard macOS size when Text size changes.
- The graphs have no per-point audio or table view yet.

Found a problem? Please [open an issue](https://github.com/Ol775/macos-task-manager/issues/new/choose).
