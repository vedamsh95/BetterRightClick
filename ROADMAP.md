# Better Right Click - Strategic Roadmap

## Goal
Make Better Right Click clearly stronger than Raycast/Alfred/BetterTouchTool for right-click-native workflows by improving:
- Features
- Stability
- Extensibility

## Product Wedge
Own the category: **Right-Click Intelligence**.

Core pillars:
1. Fast, accurate context capture.
2. Deterministic action execution.
3. User-programmable automation.

## Success Metrics
- Paste success in supported apps: **99%**.
- Menu open latency: **p95 < 250ms**.
- Context capture latency: **p95 < 500ms**.
- Action failure rate in top app matrix: **< 2%**.
- Custom action success rate: measurable and improving every release.

## Phase Plan

### Phase 1: Reliability Foundation (Weeks 1-4)
1. Replace delay-based paste with focus-verified dispatch.
2. Build centralized permission state machine (AX, Apple Events, Screen Recording).
3. Add timeout + fallback for context capture paths (Finder/AX probes).
4. Move OCR work off main thread with cancellation and progress states.
5. Harden clipboard snapshot/restore and dedupe semantics.
6. Build compatibility matrix tests for top 20 apps.

### Phase 2: Personalization and Action Registry (Weeks 5-7)
1. Introduce action registry (metadata-driven actions).
2. Replace hardcoded action rendering with registry-driven UI.
3. Add per-app/per-context action profiles.
4. Add preferences UI for action visibility and ordering.
5. Add explainability for hidden/disabled actions.

### Phase 3: Rule Engine MVP (Weeks 8-11)
1. Load YAML/JSON rules from local config folder.
2. Add condition evaluation (bundle ID, target kind, extension, text).
3. Add variable interpolation (`{context.*}`, `{file.*}`, `{selected.text}`, `{clipboard}`).
4. Add rule executor (built-in actions + subprocess + clipboard + notifications).
5. Ship starter rule packs.

### Phase 4: Workflow Chains (Weeks 10-13)
1. Add multi-step action chains with output passing.
2. Add error handlers/retry strategy per step.
3. Start with linear workflow editor UI.
4. Add local audit trail for each workflow run.

### Phase 5: Plugin SDK (Weeks 14-18)
1. Define plugin manifest and discovery model.
2. Implement JSON stdin/stdout plugin IPC.
3. Add timeout + structured error handling for plugin execution.
4. Register plugin actions in same action registry.
5. Publish plugin docs and templates.

### Phase 6: Differentiation Features (Weeks 19-24)
1. Context Action Graph presets (one-tap multi-step automations).
2. Per-app execution strategies (paste mode, focus mode, fallback mode).
3. File intelligence pack: batch rename, dedupe, archive templates, metadata ops.
4. Diagnostics with one-click remediation actions.

### Phase 7: Distribution and Trust (Weeks 25-28)
1. Dual distribution tracks:
   - Full Power (direct download)
   - MAS-safe (feature-gated)
2. Add clear on-device privacy messaging.
3. Add release checklist and gates.

## Architecture Workstreams

### Refactor Targets
- `Sources/Core/MenuWindowManager.swift`: split into smaller coordinators.
- `Sources/Services/ContextService.swift`: add bounded capture + caching.
- `Sources/Services/ClipboardService.swift`: improve reliability under rapid changes.
- `Sources/UI/ActionsTab.swift`: move to registry-driven rendering.

### New Core Components
- `ActionRegistry`
- `PasteCoordinator`
- `RuleEngine`
- `WorkflowExecutor`
- `PluginExecutor`
- `DiagnosticsModel`
- `PreferencesService`

## Verification Gates
1. Build gate each milestone:
   - `xcodebuild -project "BetterRightClick.xcodeproj" -scheme "BetterRightClick" build`
2. Reliability gate:
   - 100-run paste benchmark across app matrix.
3. Performance gate:
   - measure p95 menu open + context capture per release.
4. Stability gate:
   - 2-hour soak test with no crashes or monitor leaks.
5. Diagnostics gate:
   - every failed action must provide actionable reason.

## Strategy Notes
- Compete on depth in right-click context workflows, not generic launcher breadth.
- Do not expand feature surface until core reliability KPIs are met.
- Keep local-first trust narrative explicit in UX and docs.
