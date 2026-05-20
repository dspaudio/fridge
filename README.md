# Fridge

Fridge는 Claude Code, Codex CLI, Cursor Agent 같은 AI coding agent를 종료하지 않고 잠시 멈추는 macOS 메뉴바 앱입니다.

> AI를 종료하지 않는다. 행동권만 잠시 얼린다.

## 먼저 읽어 주세요

이 저장소는 완성형 범용 OSS 제품이나 모든 요청을 PR로 받아 기능을 계속 붙이는 공장형 프로젝트가 아닙니다. Fridge는 제가 실제로 쓰는 macOS AI coding agent 환경을 기준으로 만든 실험적 도구입니다. 공개 목적은 “그대로 설치하면 모두에게 맞는 제품”이라기보다 “구현 방식과 작업 이력을 참고해 자기 agent 환경에 맞게 포크해서 고쳐 쓰는 출발점”에 가깝습니다.

Claude Code, Codex CLI, Cursor Agent, MCP 서버 구성, terminal/tmux 습관, macOS 권한 상태는 사용자마다 다릅니다. 특정 워크플로우 호환성, Windows/Linux 지원, 개인 설정 UI, 특정 agent hook 정책 같은 요구는 이 저장소의 기본 우선순위가 아닙니다. 필요하면 포크해서 freeze 대상 분류를 바꾸고, hook 설치 경로를 조정하고, GUI를 덜어내거나 붙여서 자기 냉장고로 만들면 됩니다.

**PR welcome보다는 Fork welcome. 이슈는 버그 리포트와 구현 참고용으로만 봅니다.**

## 핵심 개념

Fridge는 kill switch가 아닙니다. 프로세스를 종료하지 않고 `SIGSTOP`으로 실행권만 멈춘 뒤, `SIGCONT`로 다시 이어서 실행합니다. 메모리, 터미널 상태, agent context를 최대한 유지하는 것이 목표입니다.

현재 기본 정책은 안전 우선입니다.

- Codex CLI, Claude Code, Cursor 같은 루트 CLI 프로세스는 멈추지 않습니다.
- 실제 작업 child process만 freeze합니다.
- MCP 서버와 Fridge 자체 프로세스는 freeze 대상에서 제외합니다.
- freeze 대상이 안전하지 않으면 실행을 거절합니다.

## 주요 기능

- SwiftUI + AppKit 기반 macOS 메뉴바 앱
- `NSStatusItem` 메뉴와 SF Symbols 상태 아이콘
- Pause/F15 글로벌 hot key로 freeze/resume toggle
- AI 프로세스 감지: `claude`, `codex`, `cursor`, `agent`, 관련 `node` child
- 프로세스 트리 탐색 및 child-only freeze/resume
- Control Panel GUI
- 권한 온보딩 창: Accessibility, Input Monitoring 안내, relaunch
- CLI helper 설치/해제: `~/.local/bin/fridge`
- Agent hook bridge 설치/해제: Codex, Claude, Cursor 안내
- activity log, hook log, git diff snapshot, rollback
- network freeze는 실제 firewall 변경 없이 guarded plan으로만 제공

## 빌드와 실행

디버그 빌드:

```sh
swift build
.build/debug/fridge status
```

macOS 앱 번들 생성:

```sh
scripts/build-app.sh
open dist/Fridge.app
```

번들은 기본적으로 ad-hoc 서명됩니다. 안정적인 macOS 권한 UX를 위해서는 Apple Development 또는 Developer ID 인증서로 서명하는 것을 권장합니다.

```sh
FRIDGE_CODESIGN_IDENTITY="Apple Development: ..." scripts/build-app.sh
```

## 0.1 릴리즈 실행 주의사항

현재 0.1 릴리즈 빌드는 Apple Developer 인증서로 서명되지 않은 개발용 ad-hoc 서명 앱입니다. 이 때문에 macOS에서 다음 현상이 발생할 수 있습니다.

- 최초 실행 시 “확인되지 않은 개발자” 또는 손상된 앱처럼 보이는 Gatekeeper 경고가 뜰 수 있습니다.
- Accessibility/Input Monitoring 같은 Privacy 권한이 앱 재빌드 후 다시 요구될 수 있습니다.
- System Settings에서 “종료 및 다시 열기”를 눌러도 앱이 자동으로 다시 열리지 않을 수 있습니다.
- 권한을 부여했는데 앱에 반영되지 않으면 Fridge를 완전히 종료한 뒤 같은 `Fridge.app` 번들을 다시 실행해야 합니다.

로컬에서 받은 zip을 실행할 때 Gatekeeper quarantine 때문에 열리지 않으면 다음을 확인하세요.

```sh
xattr -dr com.apple.quarantine Fridge.app
open Fridge.app
```

보안상 출처를 신뢰할 수 있는 빌드에서만 위 명령을 사용하세요. 정식 배포에는 Developer ID 서명과 notarization이 필요합니다.

## CLI 명령

```sh
fridge status
fridge freeze
fridge resume
fridge toggle
fridge snapshot
fridge snapshots
fridge rollback <snapshot-id>
fridge activity
fridge hook codex stop '{"reason":"user"}'
fridge install-cli
fridge uninstall-cli
fridge install-hooks
fridge uninstall-hooks
fridge install-status
fridge network-freeze
fridge mcp-proxy manifest
```

## GUI 사용법

메뉴바에서 Fridge 아이콘을 클릭하면 다음을 제어할 수 있습니다.

- 현재 앱 실행 상태와 PID 확인
- 감지된 AI 프로세스 확인
- Freeze All AI / Resume All
- Frozen PID 확인
- CLI helper 설치/해제
- Agent hooks 설치/해제
- Control Panel 열기
- Permissions 창 열기
- Quit Fridge

Control Panel에서는 설치 상태, 권한 상태, freeze/resume, relaunch, quit을 버튼으로 제어합니다.

## 권한과 재실행

macOS 권한은 앱이 자동으로 부여할 수 없습니다. Fridge는 권한 요청 UI와 System Settings 이동만 제공합니다.

- Accessibility: 글로벌 Pause 키와 자동화 표면에 필요할 수 있습니다.
- Input Monitoring: 현재 Carbon hot key 방식에서는 선택적입니다. 저수준 key event tap을 쓰는 경우 필요합니다.
- 권한을 변경한 뒤에는 Fridge를 재실행해야 현재 프로세스에 새 권한이 안정적으로 반영됩니다.

ad-hoc 서명 앱은 빌드할 때마다 TCC가 다른 앱처럼 볼 수 있습니다. 권한이 계속 반영되지 않으면 기존 Fridge 항목을 Privacy 설정에서 제거하고, 같은 `dist/Fridge.app`을 다시 추가한 뒤 relaunch하세요.

## 프로젝트 구조

- `App/`: SwiftUI 앱 진입점
- `UI/`: 메뉴바, Control Panel, 권한 창, hot key
- `Core/`: 서비스 조합, 권한, 설치, snapshot, hook, MCP proxy
- `ProcessWatcher/`: 프로세스 조회, AI 분류, tree 탐색
- `FreezeController/`: `SIGSTOP`/`SIGCONT`, frozen PID 저장
- `Models/`: 공유 모델
- `CLI/`: `fridge` CLI
- `Assets/`: 앱 아이콘 원본
- `scripts/`: 앱 번들 빌드 스크립트

## 검증된 동작

Pause 테스트에서 `sleep 120` child process만 frozen PID로 잡혔고, Codex 루트와 MCP 서버는 살아 있음을 확인했습니다.

- frozen child: `sleep 120` 상태 `T`
- Codex 루트: 실행 유지
- MCP 서버: `S` 상태 유지
- Resume All 후 frozen child 정상 resume

## 남은 과제

- Apple Development/Developer ID 서명 및 notarization
- Xcode 프로젝트 또는 설치 패키지 구성
- 더 정교한 agent별 작업 child classifier
- 실제 MCP server 형태의 proxy 제공
- privileged helper 기반 선택적 network policy
