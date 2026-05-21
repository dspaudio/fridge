# Fridge 작업 이력

## 1. 저장소 초기화와 기여자 문서

- 빈 Git 저장소 상태에서 `AGENTS.md`를 작성했다.
- 현재 저장소가 아직 앱 구조를 갖추기 전이었기 때문에 `src/`, `tests/`, `assets/`, `docs/` 기준을 안내하는 contributor guide로 시작했다.

## 2. macOS 메뉴바 MVP 구현

- Swift Package 기반 프로젝트를 구성했다.
- 실행 타깃은 `FridgeApp` 메뉴바 앱과 `fridge` CLI helper로 나누었다.
- 요청된 디렉터리 구조를 반영했다.
  - `App/`
  - `Core/`
  - `ProcessWatcher/`
  - `FreezeController/`
  - `Models/`
  - `CLI/`
  - `UI/`
- `NSStatusItem` 기반 메뉴바 앱을 구현했다.
- 초기 메뉴에는 감지된 AI 프로세스, Freeze All AI, Resume All, frozen PID 표시, 설정/종료 항목을 넣었다.

## 3. 프로세스 감지와 freeze/resume

- `/bin/ps -axo pid=,ppid=,stat=,comm=,args=` 출력으로 프로세스를 조회했다.
- `claude`, `codex`, `cursor`, `agent`, 관련 `node` child 프로세스를 감지했다.
- 초기에 `agent` 문자열이 macOS의 여러 `*Agent` 시스템 프로세스를 과탐지해, `agent` 매칭을 보수적으로 좁혔다.
- `SIGSTOP`과 `SIGCONT`를 사용해 프로세스 freeze/resume을 구현했다.
- frozen PID는 `~/.fridge/frozen-pids.json`에 저장했다.

## 4. CLI helper 구현

- `fridge status`
- `fridge freeze`
- `fridge resume`
- `fridge toggle`
- `fridge snapshot`
- `fridge rollback`
- `fridge activity`
- `fridge hook`
- `fridge network-freeze`
- `fridge mcp-proxy`
- `fridge install-cli`
- `fridge install-hooks`
- `fridge install-status`

초기 `ps` 실행에서 파이프 deadlock이 발생했기 때문에 `stdout`/`stderr`를 먼저 drain한 뒤 `waitUntilExit()`하도록 수정했다.

## 5. 확장 기능 추가

- git diff snapshot과 reverse-apply rollback을 추가했다.
- hook event JSONL 로그를 추가했다.
- activity JSONL 로그를 추가했다.
- network freeze는 macOS `pf` 또는 Network Extension 권한이 필요한 영역이라 실제 변경 대신 guarded plan 출력으로 제한했다.
- MCP proxy는 `manifest`와 단순 JSON-RPC `tools/list`, `tools/call` 표면을 추가했다.

## 6. Pause 키와 GUI 제어

- Carbon `RegisterEventHotKey`로 Pause/F15 글로벌 hot key 등록을 추가했다.
- 메뉴바의 `Settings` 안내를 실제 Control Panel 창으로 대체했다.
- Control Panel에서 다음을 제어하도록 했다.
  - CLI helper 설치/해제
  - Agent hooks 설치/해제
  - Accessibility/Input Monitoring 안내
  - Freeze All AI / Resume All
  - Relaunch / Quit
- 메뉴에도 Fridge 앱 자체 실행 상태와 PID를 표시하도록 했다.
- 정상 종료가 어렵다는 피드백을 반영해 `Quit Fridge`를 항상 보이는 앱 제어 영역에 배치했다.

## 7. 권한 UX 개선

- Accessibility 권한 상태를 `AXIsProcessTrusted()`로 확인했다.
- `Request Accessibility`, `Open Accessibility Settings`, `Open Input Monitoring Settings`, `Relaunch Fridge` 버튼을 추가했다.
- macOS 권한 변경 후 현재 프로세스에 즉시 반영되지 않을 수 있어 relaunch UX를 추가했다.
- 권한 창에 Bundle ID, 앱 경로, codesign 요약을 표시했다.
- Input Monitoring은 현재 구현에서 필수가 아니므로 `Optional`로 표시했다.

## 8. 앱 번들, 아이콘, 서명

- `scripts/build-app.sh`를 추가해 `dist/Fridge.app`을 생성했다.
- `Assets/AppIcon.svg`를 만들고 `magick`, `sips`, `iconutil`로 `AppIcon.icns`를 생성했다.
- `Info.plist`에 앱 이름, Bundle ID, 권한 설명, 아이콘을 넣었다.
- 내부 실행 파일 이름 충돌을 해결했다.
  - 앱 실행 파일: `Contents/MacOS/Fridge`
  - CLI 실행 파일: `Contents/MacOS/fridge-cli`
- 번들 생성 후 `codesign --force --deep --sign -`로 ad-hoc 서명했다.
- `CFBundleIdentifier`가 codesign identifier로 잡히도록 수정했다.

## 9. Agent hook 설치

- 앱 설치가 아니라 agent hook 설치가 필요하다는 피드백을 반영했다.
- CLI helper 설치는 `~/.local/bin/fridge` shim으로 구현했다.
- Agent hook bridge는 `~/.fridge/hooks/fridge-agent-hook.sh`에 설치한다.
- Codex hooks는 `~/.codex/hooks.json`에 Fridge marker가 있는 hook entry를 병합/삭제한다.
- Claude hooks는 `~/.claude/settings.json`에 병합/삭제한다.
- Cursor는 배포별 hook 표면이 달라 `~/.fridge/agents/cursor-hook-bridge.md` 안내 파일을 만든다.

## 10. Freeze 정책 수정

초기 freeze는 Codex CLI 루트와 MCP child까지 멈출 수 있었다. 이는 제품 철학과 맞지 않아 정책을 수정했다.

현재 정책:

- Codex CLI, Claude Code, Cursor 루트 프로세스는 freeze하지 않는다.
- 현재 Fridge CLI를 호출한 프로세스 경로와 겹치는 경우 freeze를 거절한다.
- 기본 freeze 대상은 AI 프로세스의 child process다.
- MCP/도구 인프라는 freeze 대상에서 제외한다.
  - `oh-my-codex/dist/mcp`
  - `mcp-server`
  - `wiki-server`
  - `memory-server`
  - `state-server`
  - `trace-server`
  - `code-intel-server`

## 11. Pause 테스트 결과

테스트 절차:

1. `sleep 120`을 child process로 실행했다.
2. Pause 키를 눌렀다.
3. Fridge 메뉴에서 frozen PID가 `63245`로 표시됐다.
4. `ps`로 확인한 결과 `63245`는 `sleep 120`이고 상태는 `Ts`였다.
5. Fridge 앱, Codex 루트, MCP 서버들은 `S` 상태로 살아 있었다.
6. `fridge resume` 후 frozen child를 resume했고, 테스트용 `sleep`을 종료했다.

결론:

- 루트 CLI는 멈추지 않았다.
- MCP 서버는 멈추지 않았다.
- 실제 child 작업만 freeze됐다.

## 12. Agent hook freeze context 전달

- freeze 시점에 `~/.fridge/freeze-context.json`을 저장하도록 추가했다.
- 저장 정보에는 다음을 포함한다.
  - 무엇이 얼었는지: frozen PID와 감지된 프로세스 요약
  - 왜 얼었는지: CLI, 메뉴, Control Panel, MCP 등 호출 source와 reason
  - 다시 녹이면 어디서 이어지는지: `fridge resume`/`SIGCONT` 후 기존 suspended instruction과 terminal/session context에서 이어진다는 설명
- `fridge hook <source> <event> [payload]`는 hook 로그 기록과 함께 agent가 바로 읽을 수 있는 JSON을 stdout으로 출력한다.
- hook JSON에는 `fridgeState`, `frozenPIDs`, `detectedProcesses`, `freezeContext`, `message`를 포함한다.

## 13. 0.2 릴리즈

- `CFBundleShortVersionString`을 `0.2.0`, `CFBundleVersion`을 `2`로 올렸다.
- MCP proxy manifest 버전을 `0.2.0`으로 올렸다.

## 14. Hook awareness와 thaw 판단

- hook payload에 `fridgeAwareness`를 항상 포함해, agent가 Fridge hook이 설치되어 있고 AI child process를 `SIGSTOP`/`SIGCONT`로 freeze/resume할 수 있음을 인지하도록 했다.
- hook bridge가 stdin payload를 읽어 `fridge hook`으로 넘기도록 바꿨다.
- hook payload에 `hookContext`를 추가해 `lastTool`, `cwd`, `pendingPromptSummary`를 구조화했다.
- hook payload에 `resumeProbe`와 `thawResult`를 추가했다.
  - `resumeProbe`: child 생존 여부, TTY 연결 여부, 남은 frozen PID, 사라진 PID
  - `thawResult`: `resumed`, `child_gone`, `tty_lost`, `unsafe_to_resume`
- `agentInstruction`을 추가해 hook을 받은 agent가 바로 다음 행동을 판단할 수 있게 했다.
- 기본 hook 설치 이벤트를 `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `SessionEnd`로 넓혔다.
- `ps`에서 TTY를 함께 파싱하고, freeze/resume 직후 터미널에 `FREEZED:`/`RESUMED:` best-effort notice를 남기도록 추가했다.

## 15. 0.3 릴리즈

- `CFBundleShortVersionString`을 `0.3.0`, `CFBundleVersion`을 `3`으로 올렸다.
- MCP proxy manifest 버전을 `0.3.0`으로 올렸다.

## 16. Hook 출력 정책과 0.3.1 릴리즈

- `fridge hook` 기본 stdout을 전체 multiline JSON 대신 짧은 한 줄 message로 바꿨다.
- 전체 hook payload는 기존 hook log에 계속 기록한다.
- 진단용 출력 옵션으로 `--json`, `--compact`, `--quiet`을 추가했다.
- `CFBundleShortVersionString`을 `0.3.1`, `CFBundleVersion`을 `4`로 올렸다.
- MCP proxy manifest 버전을 `0.3.1`로 올렸다.

## 17. Hook quiet bridge와 0.3.2 릴리즈

- `Stop`, `SessionEnd` hook bridge 호출은 `--quiet`로 전달해 종료 hook stdout noise를 줄였다.
- `CFBundleShortVersionString`을 `0.3.2`, `CFBundleVersion`을 `5`로 올렸다.
- MCP proxy manifest 버전을 `0.3.2`로 올렸다.

## 18. Fn double-tap freeze와 0.4.0 릴리즈

- Pause/F15 경로는 유지하면서 Fn 두 번 누르기로 같은 freeze 경로를 타도록 추가했다.
- freeze context에 `activeTaskDescription`을 추가하고, 최근 hook metadata에서 `lastTool`, `cwd`, `pendingPromptSummary`를 복원해 다음 hook payload로 다시 전달하도록 보강했다.
- `CFBundleShortVersionString`을 `0.4.0`, `CFBundleVersion`을 `6`으로 올렸다.
- MCP proxy manifest 버전을 `0.4.0`으로 올렸다.

## 19. 현재 제약과 다음 과제

- 현재 번들은 ad-hoc 서명이다. 안정적인 TCC 권한 UX에는 Apple Development 또는 Developer ID 서명이 필요하다.
- Input Monitoring은 현재 Carbon hot key 방식에서는 필수 권한이 아니다.
- agent별 실제 작업 child classifier를 더 정교하게 개선할 여지가 있다.
- network freeze는 실제 구현하려면 privileged helper 또는 Network Extension 설계가 필요하다.
- MCP proxy는 현재 CLI 기반 최소 표면이며, 실제 MCP server로 분리할 수 있다.
