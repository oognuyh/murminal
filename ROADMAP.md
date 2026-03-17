# Murminal Roadmap Proposal

> 경쟁 앱(Moshi, Termius, Blink Shell, Wave Terminal, Warp, Tabby) 분석 기반
> **Voice-First Terminal** 로드맵

---

## 경쟁 분석 요약

### 모바일 SSH 클라이언트

| 앱 | 핵심 차별점 | Murminal과의 비교 |
|---|---|---|
| **Moshi** | AI 에이전트 모니터링 특화, 음성→터미널(on-device Whisper), Push 알림, Mosh 프로토콜 | 가장 직접적인 경쟁자. Murminal이 더 다양한 AI 프로바이더와 Engine Profile을 지원 |
| **Termius** | 크로스플랫폼, 팀 협업, 클라우드 동기화, AI 자동완성, SFTP | 엔터프라이즈급 기능(팀, Vault). Murminal은 음성 AI에 집중 |
| **Blink Shell** | iOS 최고의 Mosh 클라이언트, VS Code 통합, 오픈소스 | 안정적인 Mosh 지원이 강점. Murminal은 AI 음성 통합에서 차별화 |
| **VVTerm** | Ghostty 기반 렌더링, on-device Voice-to-Command (MLX Whisper), Apple 생태계 통합 | 음성 명령 기능이 유사하나, Murminal은 AI 대화형 + 도구 실행까지 지원 |

### 터미널 Superset (데스크톱)

| 앱 | 핵심 차별점 | 참고 포인트 |
|---|---|---|
| **Wave Terminal** | 그래픽 위젯, 파일 프리뷰(마크다운/이미지/PDF/CSV), AI 채팅 패널, 로컬 AI(Ollama) | 터미널 안에서 시각적 콘텐츠를 보여주는 UX |
| **Warp** | Agentic IDE, Oz Agent(터미널+컴퓨터 사용), 멀티모델 AI, **음성 입력(Wispr Flow)** | 에이전트가 터미널을 직접 제어하는 패러다임 + 보이스 |
| **Tabby** | 내장 SSH/SFTP, Vault, 웹앱 버전, MCP 통합, 플러그인 생태계 | 웹앱 + 플러그인 아키텍처 |

### 보이스 경쟁 현황 (2026)

| 앱/기능 | 음성 방식 | 수준 |
|---|---|---|
| **Claude Code /voice** | Push-to-talk → 텍스트 변환 (타이핑 대체) | STT only |
| **Warp Voice** | Wispr Flow 기반 음성 입력 → Agent Mode | STT → Agent |
| **Moshi** | On-device Whisper → 터미널 텍스트 입력 | STT only |
| **VVTerm** | MLX Whisper → 커맨드 변환 | STT → Command |
| **Murminal (현재)** | Realtime API (Gemini/OpenAI/Qwen) → AI 판단 → 도구 실행 → 음성 응답 | **Full Duplex Voice Loop** |

> **Murminal은 이미 가장 진보된 음성 파이프라인을 보유.** 경쟁사는 STT(음성→텍스트) 수준이지만,
> Murminal은 음성→AI 판단→도구 실행→결과 음성 보고의 **완전한 양방향 루프**를 구현.

---

## Murminal의 현재 음성 구현 분석

### 이미 있는 것

```
┌─────────┐    ┌──────────────┐    ┌──────────────┐    ┌────────┐
│  마이크   │ →  │ Realtime API │ →  │ Tool Executor│ →  │  tmux  │
│  (PCM)   │    │ (Gemini/     │    │ send_command │    │ session│
│          │    │  OpenAI/Qwen)│    │ get_status   │    │        │
└─────────┘    └──────────────┘    │ list/create/ │    └────────┘
                     ↓              │ kill_session │         ↓
               ┌──────────────┐    └──────────────┘    ┌────────┐
               │ 음성 응답     │ ←  Pattern Detector  ← │ Output │
               │ (TTS/PCM)    │    + Report Generator   │Monitor │
               └──────────────┘                         └────────┘
```

- **6개 도구**: send_command, get_session_status, list_sessions, create_session, kill_session, get_all_sessions
- **2가지 파이프라인**: Realtime (WebSocket) / Local (on-device STT+TTS + LM API)
- **프로액티브 리포팅**: 터미널 출력 변경 → 패턴 감지 → 자동 음성 보고
- **오디오 인터럽션 처리**: 전화/Siri 등 중단 시 자동 복구
- **에러 복구 음성 알림**: SSH 연결 끊김/복구 자동 보고

### 아직 없는 것 (Voice Gap Analysis)

| 빠진 기능 | 설명 | 경쟁사 참고 |
|---|---|---|
| **Wake Word** | 버튼 없이 "Hey Murminal"로 활성화 | 일반적 Voice Assistant 패턴 |
| **보이스 단축 명령** | "Ctrl+C", "스크롤 위로" 같은 직접 제어 | VVTerm Voice-to-Command |
| **보이스 네비게이션** | "서버 목록 보여줘", "설정 열어" — 앱 UI 자체를 음성으로 탐색 | Warp Voice + Agent Mode |
| **보이스 딕테이션** | AI 해석 없이 말한 그대로 터미널에 타이핑 | Claude Code /voice, Moshi |
| **대화 맥락 유지** | "아까 그 에러 다시 보여줘" — 세션 간 대화 히스토리 | ChatGPT Voice 스타일 |
| **보이스 매크로** | 자주 쓰는 음성 명령을 저장/재사용 | Termius Snippets + Voice |
| **멀티모달 응답** | 음성 + 화면 하이라이트 동시 피드백 | Wave Terminal 위젯 |
| **보이스 인증** | 음성으로 위험한 명령 확인 ("정말 삭제할까요?") | 보안 Best Practice |
| **Ambient Listening** | 백그라운드에서 계속 듣다가 중요 이벤트에만 반응 | Smart Speaker 패턴 |

---

## Voice-First 로드맵

### Phase 0: 보이스 코어 강화 (Voice Core)

> 현재 음성 루프의 기본 완성도를 높이는 단계

#### 0.1 보이스 딕테이션 모드 (Voice Dictation)
- **Why**: Claude Code /voice, Moshi 모두 "말한 것을 그대로 타이핑"하는 기본 모드 제공. 현재 Murminal은 모든 음성을 AI가 해석하므로, 단순 타이핑 시 오버헤드가 발생
- **What**:
  - 토글 가능한 딕테이션 모드: 음성 → on-device STT → 그대로 tmux send-keys
  - AI 모드 ↔ 딕테이션 모드 빠른 전환 (더블탭 or 음성 명령 "딕테이션 모드")
  - 딕테이션 시 AI 비용 제로
- **Impact**: API 비용 없이 터미널에 음성으로 타이핑 가능. 간단한 명령은 AI 없이 직접 입력

#### 0.2 보이스 단축 명령 (Voice Shortcuts)
- **Why**: "Ctrl+C", "위로 스크롤", "탭 키" 같은 빈번한 조작을 음성으로 할 수 없으면 결국 터치에 의존
- **What**:
  - 키 조합 매핑: "컨트롤 씨" → Ctrl+C, "탭" → Tab, "엔터" → Enter
  - 터미널 조작: "위로 스크롤", "클리어", "취소"
  - tmux 조작: "새 패인", "패인 전환", "줌"
  - on-device STT로 저지연 처리 (AI 불필요)
- **Impact**: 키보드 없이 완전한 터미널 조작 가능. 진정한 hands-free

#### 0.3 대화 컨텍스트 유지 (Conversation Memory)
- **Why**: 현재 매 턴마다 시스템 프롬프트를 새로 빌드하지만, 이전 대화 맥락이 유지되지 않으면 "아까 그거"가 동작하지 않음
- **What**:
  - 최근 N턴의 대화 히스토리를 시스템 프롬프트에 포함
  - 세션별 대화 로그 저장/검색
  - "아까 실행한 명령 다시 해줘" 같은 참조 해결
- **Impact**: 자연스러운 연속 대화. 반복 설명 불필요

---

### Phase 1: 보이스 인터랙션 확장 (Voice Interaction)

> 음성으로 앱 전체를 제어할 수 있게 확장

#### 1.1 보이스 네비게이션 (Voice Navigation)
- **Why**: Warp가 음성으로 Agent Mode에 진입하듯, Murminal도 앱 UI 자체를 음성으로 탐색해야 함
- **What**:
  - 앱 네비게이션 음성 명령: "서버 목록", "설정", "세션 목록", "홈"
  - 서버 선택: "HomeLab 서버 연결해줘"
  - 세션 전환: "Claude Code 세션으로 전환"
  - GoRouter와 연동하여 음성 → 라우팅 직접 매핑
- **Impact**: 한 손도 쓰지 않고 앱의 모든 화면 탐색 가능

#### 1.2 Wake Word / Always-On 리스닝
- **Why**: 현재는 버튼을 눌러야 음성 입력 시작. 진짜 hands-free를 위해서는 호출어 감지 필요
- **What**:
  - "Hey Murminal" 또는 커스텀 호출어 감지
  - on-device 처리 (Picovoice Porcupine 또는 iOS SFSpeechRecognizer 활용)
  - 배터리 영향 최소화를 위한 저전력 리스닝 모드
  - 설정에서 On/Off 토글
- **Impact**: 폰을 들고 있지 않아도 음성으로 바로 명령 가능

#### 1.3 보이스 컨펌 (Voice Confirmation)
- **Why**: `rm -rf`, `kill_session` 같은 위험한 명령 실행 전 확인이 필요
- **What**:
  - 위험 명령 분류 (destructive commands 리스트)
  - AI가 "정말로 세션을 삭제할까요?"라고 음성으로 확인
  - "네" / "아니오"로 응답하면 실행 또는 취소
  - 확인 없이 실행할 명령 화이트리스트 설정 가능
- **Impact**: 음성 제어의 안전성 확보. 실수로 위험한 명령 실행 방지

---

### Phase 2: 보이스 + 에이전트 모니터링 (Voice Agent Control)

> 음성을 통한 AI 에이전트 관제 시스템

#### 2.1 Ambient Listening 모드
- **Why**: 에이전트가 장시간 작동할 때, 계속 화면을 보지 않고 중요한 이벤트만 음성으로 알려주는 모드
- **What**:
  - 백그라운드에서 패턴 감지 + 선별적 음성 보고
  - 보고 레벨 설정: 전부 / 에러+완료만 / 완료만 / 질문만
  - AirPods/Bluetooth 이어폰으로 계속 듣기
  - 잠금 화면에서도 음성 보고 (Now Playing 컨트롤 활용)
- **Impact**: "팟캐스트 듣듯이" 에이전트 상태를 수동적으로 모니터링. 라디오처럼 흘려듣기

#### 2.2 보이스 인터벤션 (Voice Intervention)
- **Why**: 에이전트가 질문하거나 에러가 나면 즉시 음성으로 개입해야 함
- **What**:
  - 에이전트 질문 감지 → Push 알림 + 음성 "에이전트가 질문합니다: ..."
  - 알림에서 바로 음성 답변 → AI가 해석 → send_command로 에이전트에 전달
  - 에러 감지 → "에러가 발생했어요. 재시도할까요?"
  - Quick Voice Actions: "재시도", "스킵", "중단"
- **Impact**: 산책 중에도 에이전트에 즉각 응답 가능. 에이전트 대기 시간 최소화

#### 2.3 멀티세션 보이스 제어
- **Why**: 여러 에이전트를 동시에 돌릴 때, 음성으로 특정 세션 지정이 필요
- **What**:
  - "Claude Code 세션 상태 알려줘" → 특정 세션 타겟팅
  - "전체 세션 요약해줘" → 모든 세션 상태 브리핑
  - "3번 세션에 git push 보내줘" → 세션 번호로 빠른 지정
  - 보이스로 세션 간 전환: "다음 세션", "이전 세션"
- **Impact**: 다중 에이전트 환경에서 음성만으로 전체 관제

---

### Phase 3: 보이스 인텔리전스 (Voice Intelligence)

> AI 음성 파이프라인의 지능 고도화

#### 3.1 컨텍스트 어웨어 보이스 (Context-Aware Voice)
- **Why**: 현재 음성 AI는 시스템 프롬프트에 세션 목록만 포함. 더 풍부한 컨텍스트 제공 필요
- **What**:
  - 현재 터미널 출력을 AI 컨텍스트에 자동 포함 (가장 최근 N줄)
  - Engine Profile의 상태 정보(thinking/error/complete)를 컨텍스트에 반영
  - 파일 시스템 컨텍스트: "방금 수정한 파일 뭐야?" → git status 자동 실행
  - 서버 상태 컨텍스트: CPU, 메모리, 디스크 정보
- **Impact**: 더 정확한 음성 응답. "지금 뭐 하고 있어?"에 구체적으로 답변 가능

#### 3.2 보이스 매크로 & 워크플로우 (Voice Macros)
- **Why**: Termius Snippets처럼 자주 쓰는 명령을 저장하되, 음성 트리거로 실행
- **What**:
  - "배포해줘" → 미리 정의된 deploy 스크립트 실행
  - "테스트 돌려" → npm test 실행 + 결과 대기 + 음성 보고
  - 사용자 정의 음성 매크로 에디터
  - 조건부 워크플로우: "테스트 통과하면 배포해줘"
- **Impact**: 복잡한 작업을 한마디로 실행. Siri Shortcuts처럼 자동화

#### 3.3 다국어 보이스 (Multilingual Voice)
- **Why**: 현재 언어 설정이 있으나, 실시간 다국어 전환 미지원
- **What**:
  - 한국어 ↔ 영어 자동 감지 및 전환
  - 한국어 명령 → 영어 셸 커맨드 변환 ("파일 목록 보여줘" → `ls -la`)
  - 보이스 응답 언어 선택 (입력 한국어 / 출력 영어 가능)
  - 기술 용어 혼용 자연 처리 ("git push 해줘", "docker 재시작")
- **Impact**: 한국어 화자가 자연스럽게 터미널을 음성 제어

---

### Phase 4: 기반 & 연결 강화 (Infrastructure)

> 음성 경험을 뒷받침하는 인프라

#### 4.1 Mosh 프로토콜 지원
- **Why**: Moshi, Blink Shell 모두 Mosh 핵심 지원. 음성 제어 중 연결 끊김은 UX 파괴
- **What**: dartssh2 외에 Mosh 클라이언트 통합 (Rust FFI)
- **Impact**: 지하철, Wi-Fi↔셀룰러 전환 시에도 음성 세션 유지

#### 4.2 Push Notification + 보이스 응답
- **Why**: Moshi의 킬러 피처를 음성과 결합
- **What**:
  - Pattern Detector "complete"/"error"/"question" → Push 알림
  - 알림 Long Press → 바로 음성 응답 모드 진입
  - 알림 내 Quick Actions: "재시도", "상태 확인", "음성 연결"
- **Impact**: 앱을 열지 않고도 음성으로 에이전트에 응답

#### 4.3 리치 보이스 피드백 (Voice + Visual)
- **Why**: Wave Terminal처럼 시각적 피드백을 음성과 결합
- **What**:
  - 음성 응답 시 관련 터미널 부분 하이라이트
  - 에러 보고 시 에러 라인으로 자동 스크롤 + 하이라이트
  - 음성 명령 실행 결과를 요약 카드(diff, status)로 표시
  - "보여줘" 명령 시 관련 출력을 시각적으로 확대 표시
- **Impact**: 음성만으로 부족한 상세 정보를 시각적으로 보완. 멀티모달 경험

---

### Phase 5: 생태계 확장 (Ecosystem)

#### 5.1 보이스 프로파일 마켓플레이스
- **Why**: Tabby의 플러그인 + Engine Profile을 음성 매크로까지 확장
- **What**:
  - Engine Profile + Voice Macro + Voice Shortcut 패키지를 공유
  - "Claude Code 보이스 팩", "DevOps 보이스 팩" 같은 번들
  - 커뮤니티 기여 및 다운로드
- **Impact**: 새로운 AI 도구나 워크플로우에 빠른 음성 지원 추가

#### 5.2 서버/세션 클라우드 동기화
- **Why**: Termius의 클라우드 Vault
- **What**: E2E 암호화 동기화 (서버, Engine Profile, 보이스 매크로, API 키)
- **Impact**: 디바이스 전환 시 음성 설정까지 자동 동기화

#### 5.3 MCP 서버 통합
- **Why**: AI 에이전트 생태계 표준 프로토콜
- **What**: Murminal을 MCP 서버로 — 외부 에이전트가 음성 피드백을 Murminal을 통해 전달
- **Impact**: 에이전트 생태계와의 양방향 통합

---

## 우선순위 매트릭스

```
             높은 임팩트
                 │
    ┌────────────┼────────────┐
    │ Phase 0    │ Phase 2    │
    │ 딕테이션    │ Ambient    │
    │ 단축 명령   │ Listening  │
    │ 대화 맥락   │ 인터벤션    │
    ├────────────┼────────────┤
    │ Phase 1    │ Phase 3    │
    │ 네비게이션  │ 매크로      │
    │ Wake Word  │ 다국어      │
    │ 컨펌       │ 컨텍스트    │
    └────────────┼────────────┘
                 │
             낮은 임팩트
    낮은 난이도 ──────── 높은 난이도
```

**즉시 착수 권장**: Phase 0 (보이스 코어) — 기존 코드에 최소 변경으로 가장 큰 격차를 메움

---

## 핵심 메시지

> **Murminal = Voice-First Terminal Supervisor**
>
> 경쟁사들이 "음성 입력" 수준에 머무는 동안, Murminal은
> **음성으로 듣고 → AI가 판단하고 → 실행하고 → 음성으로 보고하는**
> 완전한 양방향 음성 루프를 가진 유일한 터미널.
>
> 다음 목표: **터미널의 모든 조작을 음성으로** — 키보드 없는 터미널 경험.

---

## 경쟁사 참고 링크

- [Moshi](https://getmoshi.app/) — AI 에이전트 모니터링 특화 iOS 터미널
- [VVTerm](https://www.productcool.com/product/vvterm) — Ghostty 기반 음성 SSH 클라이언트
- [Termius](https://termius.com/) — 크로스플랫폼 SSH 클라이언트 (팀/엔터프라이즈)
- [Blink Shell](https://blink.sh/) — iOS 최고의 Mosh 기반 터미널 (오픈소스)
- [Wave Terminal](https://www.waveterm.dev/) — AI + 그래픽 위젯 통합 터미널
- [Warp](https://www.warp.dev/) — Agentic Development Environment + Voice
- [Tabby](https://tabby.sh/) — 내장 SSH/SFTP + 플러그인 생태계 터미널
- [Claude Code Voice](https://claudefa.st/blog/guide/mechanics/voice-mode) — Claude Code의 음성 모드
- [Wispr Flow](https://wisprflow.ai/) — Warp의 음성 입력 엔진
