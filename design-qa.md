# Design QA

## Current run: 简历工作台生命周期重构 / 2026-08-29

final result: blocked

### Audit evidence

- Pre-refactor implementation capture: `audit-artifacts/resume-rebuild/01-current-resume.jpeg`.
- The capture shows a sample resume loaded as the only global draft, a `新建简历` button that does not directly create a blank document, and an editor whose project section is expanded by default.
- After the development bundle was rebuilt, Computer Use was blocked by the Mac lock screen before a valid post-refactor screenshot could be captured. No post-refactor visual or pointer-click claim is made here.

### Architecture verdict

- The old flow combined document creation, AI generation, draft persistence, and export-state checking in one view. `新建简历` opened the AI form and later replaced the only draft.
- The new flow separates `ResumeDocument`, `ResumeWorkspace`, `ResumeDocumentCodec`, and content-generation actions. A new document gets a new UUID and empty sections immediately; AI generation only fills the current document; export is the only save action.
- Legacy draft keys, sample data, singleton-section decoding, and unsaved-export alert gating were removed rather than migrated.

### Static implementation checks

- `swift test`: 93 tests passed.
- `swiftformat --lint`: passed for all updated resume files.
- `swiftlint`: 0 violations for all updated resume files.
- `git diff --check`: passed.
- Development bundle rebuilt at `/Users/wesley/VibeCodingProjects/贾维斯/dist/Jarvis-Dev.app`.

### Runtime blocker

The development app was relaunched, but the Mac was locked and automatic unlock was unavailable. Unlock the Mac and rerun the resume flow to verify the actual click path: `新建简历` → blank preview/basic-info editor → edit → `保存` → edit again shows `未保存`.

## Current run: 简历制作技能 / 文件名、预览位置与手风琴 / 2026-08-28

final result: blocked

### Comparison target

- Source visual truth: `/var/folders/vy/lm3tlnrd6958vss09dnd6d380000gn/T/codex-clipboard-5a4389e7-fc6e-447a-81e7-885712762b3a.png`
- Implementation capture: `/var/folders/vy/lm3tlnrd6958vss09dnd6d380000gn/T/com.openai.sky.CUAService/Jarvis-Dev Screenshot 2026-08-28 at 14.28.35.jpeg`
- Source pixels: 1867 x 1892; implementation pixels: 1195 x 768; density normalization: not applied because the source is a focused preview reference while the implementation capture is the full native app window.
- State: `技能库 > 简历`, project section expanded, production data shape preserved, development bundle `com.jarvis.mac.dev`.

### Focused comparison

- Top toolbar: implementation removes the `文件名` label and renders the title as a gray adaptive capsule with the save state immediately beside it.
- Preview: implementation adds an explicit top spacer so the document no longer starts against the canvas edge.
- Editor: implementation uses a single-open accordion; the selected project module expands below its row and pushes later rows down.
- No actionable P0/P1/P2 visual mismatch was observed in the captured state. The source is a focused preview reference and does not include the editor panel, so the full-window shell is intentionally not treated as a mismatch.

### Interaction verification blocker

Computer Use could read the final expanded state, but its native click pipe closed when clicking an accordion row. The app process remained alive and the final screenshot shows the project row expanded; click-to-switch and click-outside filename focus loss could not be verified end-to-end in this run.

### Implementation checks

- `swift test`: 89 tests passed.
- `swiftformat` on updated resume files: passed.
- `git diff --check`: passed.
- Development app rebuilt and relaunched at `/Users/wesley/VibeCodingProjects/贾维斯/dist/Jarvis-Dev.app`.

## Previous run: 简历制作技能 / 2 号视觉方向

final result: blocked

### Blocker

The production and isolated development builds compile and launch, but the
desktop is currently covered by a pre-existing Jarvis Keychain permission
dialog for `com.jarvis.mac.screenshot-translation`. Computer Use could not
obtain an eligible Jarvis window state, and dismissing or approving that
system permission would change local security state without user direction.
The captured screen therefore does not represent the resume skill and cannot
be used as a valid implementation comparison.

### Comparison artifacts

- Source visual truth: `/Users/wesley/.codex/generated_images/01a046cd-b50f-7f30-a177-7ffb9bc271e4/exec-7f2df9a2-2b23-4e97-a4b1-9a587514dde1.png`
- Source pixels: 1487 x 1058; intended desktop concept viewport: 1440 x 1024.
- Implementation capture: `/var/folders/vy/lm3tlnrd6958vss09dnd6d380000gn/T/jarvis-dev-screen2.unSaZBpcGI.png`
- Implementation pixels: 5120 x 2880 full desktop capture; no valid app-window crop was available.
- State: intended `技能库 > 简历`, edit mode, project section selected; actual capture blocked by the unrelated permission dialog.
- Focused comparison: not performed because the implementation artifact is not the same state; typography, spacing, tokens, assets, and copy remain unverified in the running app.

### Implementation checks completed

- `swift test`: 89 tests passed.
- `./build_app.sh`: production app built at `/Users/wesley/VibeCodingProjects/贾维斯/dist/Jarvis.app`.
- `swiftformat` on all updated resume and AI files: passed.
- `swiftlint` on the new resume and AI files: 0 violations; existing project warnings remain outside this change.
- `git diff --check`: passed.
- JSON import/export round-trip and real-AI response parsing tests: passed.

## Previous run: 技能库导航 / 2026-08-25

historical result: passed

## Source visual truth

- Current reference image: `/var/folders/vy/lm3tlnrd6958vss09dnd6d380000gn/T/codex-clipboard-8f44a84a-373a-489b-b508-9de0a775703d.png`
- Reference dimensions: 312 x 530 px.
- Reference focus: Telegram-style compact left rail with small outer margins, dense rows, and close-to-edge placement.
- Product state compared: 贾维斯 技能库 > 截图, with the primary sidebar and centered secondary navigation visible.

## Implementation evidence

- Skill Library screenshot: `/tmp/jarvis-sidebar-verify-2026-08-25/24-dist-telegram-spacing.png`
- Skill Library capture dimensions: 2032 x 1553 px, window-only capture; logical window viewport 1920 x 1441 pt; capture scale approximately 1.058x.
- Native window controls default state: `/tmp/jarvis-sidebar-verify-2026-08-25/31-native-standard-normal.png`
- Native window controls hover state: `/tmp/jarvis-sidebar-verify-2026-08-25/33-native-standard-hover-close.png`
- Native window controls hover captures: `/tmp/jarvis-sidebar-verify-2026-08-25/34-native-standard-hover-minimize.png`, `/tmp/jarvis-sidebar-verify-2026-08-25/35-native-standard-hover-zoom.png`
- Chat screenshot: `/tmp/jarvis-sidebar-verify-2026-08-25/12-swapped-overview.png`
- Chat capture dimensions: 2032 x 1553 px, window-only capture.
- Settings placement screenshot: `/tmp/jarvis-sidebar-verify-2026-08-25/14-settings-bottom.png`
- Native window controls screenshot: `/tmp/jarvis-sidebar-verify-2026-08-25/22-uniform-margins-native-tooltips-final.png`
- Build artifact: `/Users/wesley/VibeCodingProjects/贾维斯/dist/Jarvis.app`

## Comparison

- Full view: passed. The left rail now sits close to the window edge with a compact Telegram-like density, while the active contextual navigation remains centered above the content canvas.
- Focused view: passed. The primary sidebar uses 10 pt outer margins, 168 pt width, 8 pt internal padding, and 40 pt navigation rows; the native controls sit above the first row without overlap.
- Utility navigation: passed. 设置 is anchored to the bottom of the primary sidebar and no longer occupies the top-right shell area.
- Window chrome: passed. The native red/yellow/green window controls are placed at the top of the primary sidebar without overlapping the first navigation row.
- Window chrome interaction: passed. The implementation keeps the original `NSWindow.standardWindowButton` instances in the titlebar view hierarchy; entering the upper-left control region changes all three native traffic lights to the system glyph state (`×`, `−`, and the native zoom icon), matching the supplied reference without Toast, tooltip, overlay, or manually selected SF Symbols.
- Native adaptation: passed. The panel uses the existing macOS Liquid Glass abstraction (`jarvisGlass`) with a continuous rounded rectangle and a subtle native-style border rather than introducing a separate visual system.
- Intentional differences: the reference is a narrow cropped Telegram rail, while 贾维斯 keeps horizontal icon-plus-label rows and a rounded Liquid Glass shell for its native desktop hierarchy.

## Findings

- No P0/P1/P2 visual issues found for the selected direction.
- Grok is wired to the official `https://grok.com/` entry point. Login state and provider-side challenges remain external runtime state and are not treated as app-side visual failures.

## Comparison history

- 2026-08-25: initial implementation checked against selected option 3.
- 2026-08-25: final production package rechecked after swapping primary and secondary navigation positions.
- 2026-08-25: 设置 moved to the bottom of the primary sidebar and rechecked in the production package.
- 2026-08-25: top spacing tightened and native window controls moved into the sidebar using AppKit standard window-button factories and actions.
- 2026-08-25: Telegram reference applied; sidebar outer margins reduced and unified to 10 pt, width and row density tightened, and native button help copy reverified against the direct `dist/Jarvis.app` executable.
- 2026-08-25: replaced recreated content-view controls with the original AppKit titlebar button instances; verified the native hover glyph state against the supplied reference.
