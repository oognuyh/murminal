# Murminal Roadmap Proposal

> 경쟁 앱(Moshi, Termius, Blink Shell, Wave Terminal, Warp, Tabby) 분석을 기반으로 한 로드맵 제안

---

## 경쟁 분석 요약

### 모바일 SSH 클라이언트

| 앱 | 핵심 차별점 | Murminal과의 비교 |
|---|---|---|
| **Moshi** | AI 에이전트 모니터링 특화, 음성→터미널(on-device Whisper), Push 알림, Mosh 프로토콜 | 가장 직접적인 경쟁자. Murminal이 더 다양한 AI 프로바이더와 Engine Profile을 지원 |
| **Termius** | 크로스플랫폼, 팀 협업, 클라우드 동기화, AI 자동완성, SFTP | 엔터프라이즈급 기능(팀, Vault). Murminal은 음성 AI에 집중 |
| **Blink Shell** | iOS 최고의 Mosh 클라이언트, VS Code 통합, 오픈소스 | 안정적인 Mosh 지원이 강점. Murminal은 AI 음성 통합에서 차별화 |

### 터미널 Superset (데스크톱)

| 앱 | 핵심 차별점 | 참고 포인트 |
|---|---|---|
| **Wave Terminal** | 그래픽 위젯, 파일 프리뷰(마크다운/이미지/PDF/CSV), AI 채팅 패널, 로컬 AI(Ollama) | 터미널 안에서 시각적 콘텐츠를 보여주는 UX |
| **Warp** | Agentic IDE, Oz Agent(터미널+컴퓨터 사용), 멀티모델 AI, 코드 에디터 통합 | 에이전트가 터미널을 직접 제어하는 패러다임 |
| **Tabby** | 내장 SSH/SFTP, Vault, 웹앱 버전, MCP 통합, 플러그인 생태계 | 웹앱 + 플러그인 아키텍처 |

---

## Murminal의 현재 강점

1. **음성 AI 통합** — Gemini Live, OpenAI Realtime, Qwen Omni 등 다중 프로바이더 지원
2. **Engine Profile 시스템** — Aider, Claude Code, Copilot 등 AI 코딩 도구별 패턴 매칭
3. **Tmux 통합** — 세션 관리, 출력 모니터링, 상태 감지
4. **음성 수퍼바이저** — 마이크 → AI → 터미널 명령 실행 → 결과 음성 보고 파이프라인

---

## 로드맵 제안

### Phase 1: 기반 강화 (Core Stability)

#### 1.1 Mosh 프로토콜 지원
- **Why**: Moshi, Blink Shell 모두 Mosh를 핵심 기능으로 제공. 모바일에서 네트워크 전환 시 SSH 연결 끊김은 치명적
- **What**: dartssh2 외에 Mosh 클라이언트 통합 (Rust 기반 mosh 라이브러리 FFI 연결 검토)
- **Impact**: 지하철, Wi-Fi↔셀룰러 전환 시에도 세션 유지

#### 1.2 Push Notification (에이전트 완료 알림)
- **Why**: Moshi의 킬러 피처. 장시간 에이전트 작업 후 결과를 알림으로 받는 것이 핵심 UX
- **What**: Pattern Detector의 "complete" 상태 감지 → iOS/Android Push 알림 발송
- **Impact**: 앱을 계속 보고 있지 않아도 에이전트 작업 완료를 알 수 있음

#### 1.3 SSH 키 보안 강화
- **Why**: Moshi는 Face ID + Keychain, Termius는 Vault + 생체 인증 제공
- **What**: Secure Enclave 키 생성/저장, 생체 인증 잠금, 키 import/export 개선
- **Impact**: 보안에 민감한 사용자 신뢰 확보

---

### Phase 2: AI 에이전트 모니터링 강화 (Agent Experience)

#### 2.1 에이전트 대시보드
- **Why**: Wave Terminal의 위젯 대시보드 컨셉 + Murminal의 Engine Profile 결합
- **What**:
  - 실행 중인 에이전트 세션들의 요약 상태를 한 화면에 표시
  - Engine Profile별 상태 아이콘 (thinking, running, error, complete)
  - 각 세션의 마지막 출력 미리보기
- **Impact**: 여러 에이전트를 동시에 모니터링하는 "관제탑" UX

#### 2.2 에이전트 작업 타임라인
- **Why**: 장시간 실행되는 에이전트의 진행 과정을 시각적으로 추적
- **What**:
  - Pattern Match 이벤트를 시간순으로 기록
  - 에러/질문/완료 이벤트를 타임라인 UI로 표시
  - 특정 이벤트 탭 → 해당 시점 터미널 출력으로 이동
- **Impact**: "지난 2시간 동안 에이전트가 뭘 했는지" 빠르게 파악

#### 2.3 스마트 인터벤션 (Smart Intervention)
- **Why**: Warp의 에이전트가 "질문" 할 때 사용자에게 알리는 패턴
- **What**:
  - Engine Profile의 "question" 패턴 감지 시 푸시 알림 + 음성 보고
  - 알림에서 바로 음성으로 응답 가능 (Quick Reply)
  - 에이전트가 stuck 상태일 때 자동 감지 및 알림
- **Impact**: 에이전트가 막혔을 때 즉시 개입할 수 있는 반응 시간 단축

---

### Phase 3: 터미널 Superset 기능 (Beyond Terminal)

#### 3.1 리치 출력 프리뷰
- **Why**: Wave Terminal이 터미널 안에서 마크다운, 이미지, CSV를 렌더링하는 것이 호평
- **What**:
  - 에이전트가 생성한 파일(diff, 이미지, 마크다운)을 인라인 프리뷰
  - Git diff를 컬러 하이라이트로 표시
  - 에이전트의 코드 변경 사항을 요약 카드로 표시
- **Impact**: 모바일에서도 에이전트가 만든 결과물을 편하게 확인

#### 3.2 SFTP / 파일 매니저
- **Why**: Termius, Tabby, Blink 모두 SFTP 지원. 에이전트가 생성한 파일을 다운로드/확인하는 니즈
- **What**:
  - SSH 연결을 통한 파일 브라우저
  - 에이전트가 수정한 파일 목록 → 탭하여 내용 확인
  - 파일 다운로드/업로드
- **Impact**: 에이전트의 작업 결과물을 모바일에서 직접 확인 가능

#### 3.3 AI 채팅 패널 (보조 채팅)
- **Why**: Wave Terminal의 사이드 채팅 패널 컨셉. 음성 외에 텍스트 기반 AI 상호작용도 필요
- **What**:
  - 현재 터미널 출력을 컨텍스트로 AI에게 질문하는 채팅 UI
  - "이 에러 뭐야?", "다음에 뭘 해야 해?" 같은 빠른 질문
  - 음성과 텍스트 채팅 간 전환
- **Impact**: 음성이 불편한 상황(회의 중, 공공장소)에서도 AI 활용 가능

---

### Phase 4: 팀 & 협업 (Team Features)

#### 4.1 서버/세션 클라우드 동기화
- **Why**: Termius의 클라우드 Vault가 킬러 피처. 디바이스 간 설정 동기화
- **What**:
  - 서버 설정, Engine Profile, API 키를 E2E 암호화 클라우드 동기화
  - 멀티 디바이스 지원 (iPad + iPhone + Mac)
- **Impact**: 디바이스 전환 시 설정 재입력 불필요

#### 4.2 세션 공유 & 팀 모니터링
- **Why**: Termius 팀 플랜, Warp 팀 협업 기능 참고
- **What**:
  - 에이전트 세션 상태를 팀원과 공유 (읽기 전용)
  - 팀 대시보드에서 여러 사람의 에이전트 상태 모니터링
  - 에이전트 작업 완료 알림을 팀 채널(Slack 등)으로 전송
- **Impact**: 팀 단위로 AI 에이전트를 활용하는 워크플로우 지원

---

### Phase 5: 플랫폼 확장 (Platform Expansion)

#### 5.1 웹앱 버전
- **Why**: Tabby가 app.tabby.sh로 웹 버전 제공. 별도 설치 없이 접근 가능
- **What**:
  - Flutter Web 빌드를 활용한 웹 앱 배포
  - 에이전트 대시보드를 브라우저에서 확인
  - 데스크톱에서는 웹, 모바일에서는 네이티브 앱 사용
- **Impact**: 어디서든 에이전트 모니터링 가능

#### 5.2 플러그인 / Engine Profile 마켓플레이스
- **Why**: Tabby의 플러그인 생태계, Wave의 위젯 시스템 참고
- **What**:
  - 커뮤니티가 Engine Profile을 공유하는 마켓플레이스
  - 새로운 AI 코딩 도구가 출시될 때 빠르게 프로파일 추가
  - 커스텀 패턴 매칭 규칙 공유
- **Impact**: 커뮤니티 주도 성장, 새로운 AI 도구에 빠른 대응

#### 5.3 MCP (Model Context Protocol) 서버 통합
- **Why**: Tabby가 MCP 통합을 시작. AI 에이전트 생태계의 표준 프로토콜
- **What**:
  - Murminal이 MCP 서버로 동작하여 AI 에이전트에게 터미널 컨텍스트 제공
  - 에이전트가 Murminal을 통해 원격 서버 상태를 조회
- **Impact**: AI 에이전트 생태계와의 더 깊은 통합

---

## 우선순위 매트릭스

```
             높은 임팩트
                 │
    ┌────────────┼────────────┐
    │  Phase 2   │  Phase 1   │
    │ 에이전트    │ Mosh       │
    │ 대시보드    │ Push 알림   │
    │            │ 보안 강화   │
    ├────────────┼────────────┤
    │  Phase 4   │  Phase 3   │
    │ 팀 협업     │ 리치 프리뷰  │
    │ 클라우드    │ SFTP       │
    │            │ AI 채팅     │
    └────────────┼────────────┘
                 │
             낮은 임팩트
    낮은 난이도 ──────── 높은 난이도
```

## 핵심 메시지

> **Murminal = AI 에이전트의 모바일 관제탑**
>
> 단순한 SSH 클라이언트가 아니라, AI 코딩 에이전트를 모바일에서 모니터링하고 음성으로 제어하는
> 유일한 앱으로 포지셔닝. Moshi가 "baby monitor for AI agents"를 표방하지만,
> Murminal은 다중 AI 프로바이더 지원 + Engine Profile + 음성 수퍼바이저로 차별화.

---

## 경쟁사 참고 링크

- [Moshi](https://getmoshi.app/) — AI 에이전트 모니터링 특화 iOS 터미널
- [Termius](https://termius.com/) — 크로스플랫폼 SSH 클라이언트 (팀/엔터프라이즈)
- [Blink Shell](https://blink.sh/) — iOS 최고의 Mosh 기반 터미널 (오픈소스)
- [Wave Terminal](https://www.waveterm.dev/) — AI + 그래픽 위젯 통합 터미널
- [Warp](https://www.warp.dev/) — Agentic Development Environment
- [Tabby](https://tabby.sh/) — 내장 SSH/SFTP + 플러그인 생태계 터미널
