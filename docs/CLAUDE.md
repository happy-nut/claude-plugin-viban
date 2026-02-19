# viban - Kanban TUI Tool

Kanban board TUI tool written in zsh.

## 필수 검증

### 레이아웃 검증 (수정 후 필수)
**커밋 전 반드시 스크립트로 검증** - 추측 금지

```bash
# 카드 렌더링 검증 스크립트 실행
zsh << 'EOF'
source .claude/viban/viban 2>/dev/null || true
col_w=38; card_inner=$((col_w - 4))
# 테스트: 한글 포함 긴 제목으로 truncate 및 박스 정렬 확인
title="feat(shared): BacktestEngine 통합 및 추상화"
spinner_w=2; title_w=$((card_inner - 7 - spinner_w))
short=$(truncate_str "$title" $title_w)
content="  / #5 $short"
content_w=$(str_width "$content")
pad=$((card_inner - content_w))
border=$(gen_border $card_inner)
printf "╭%s╮\n│%s%${pad}s│\n╰%s╯\n" "$border" "$content" "" "$border"
EOF
```

**검증 항목:**
- 박스 테두리(╭╮╰╯│) 정렬
- 스피너 있을 때/없을 때 둘 다 확인
- 한글 포함 제목 truncation

## Plugin Distribution Rules

**`commands/`와 `skills/` 디렉토리는 npm 패키지에 포함되어 모든 사용자에게 노출됨.**

- 메인테이너 전용 도구(release 등)는 `docs/`에 배치
- 사용자용 커맨드만 `commands/`, `skills/`에 배치
- 커맨드/스킬 내 참조는 `/viban:{name}` 형식 사용 (`/assign` ✗, `/viban:assign` ✓)

## Dependency Management

**새 런타임 의존성 추가 시 4곳 모두 업데이트 필수:**
- `README.md` (Requirements 섹션)
- `scripts/check-deps.sh` (check_dep 호출)
- `install.sh` (install_pkg 호출)
- `skills/setup/SKILL.md` (체크 목록 + 완료 메시지)

릴리스 전 누락 여부 확인할 것.

## Release Rules

**릴리즈는 사용자가 명시적으로 요청할 때만 수행한다.**

- 버전 범프, git tag, git push --tags 를 자동으로 하지 않는다
- 사용자가 `/viban:release` 또는 "릴리즈 해줘" 라고 할 때만 수행
- 커밋은 자유롭게 하되, 릴리즈(버전 범프 + 태그 + 푸시)는 반드시 사용자 승인 후

## Workflow Rules

### Worktree-Based Workflow
- 모든 이슈 작업은 `.viban/worktrees/{ID}` 에서 격리된 워크트리로 수행
- 메인 워크트리는 사용자 작업용으로 깨끗하게 유지
- 브랜치 네이밍: `issue-{ISSUE_ID}` (예: `issue-78`)

```bash
# 1. 워크트리 생성
git worktree add -b issue-{ISSUE_ID} "$PWD/.viban/worktrees/{ISSUE_ID}" origin/main

# 2. 워크트리 안에서 작업 후 push
cd "$PWD/.viban/worktrees/{ISSUE_ID}"
git push -u origin issue-{ISSUE_ID}

# 3. PR 생성
gh pr create --title "..." --body "..."
```

- 워크트리는 `/viban:approve`가 merge 후 정리
- `/viban:reject` 시 워크트리 유지 (재작업용)

### Base Branch Sync
- Before worktree creation: `git fetch origin main`
- Before PR push: `git fetch origin main && git rebase origin/main` (inside worktree)
- Resolve conflicts if any before pushing

## Shell Script Rules

### Language Policy (Critical)

**All user-facing text in the TUI must be in English**

This includes:
- Editor templates (title, description, priority, type prompts)
- Status messages
- Error messages
- Help text
- Comments in code

```bash
# BAD: Korean in editor template
cat << EOF
우선순위: P0/P1/P2/P3
EOF

# GOOD: English in editor template
cat << EOF
Priority: P0/P1/P2/P3
EOF
```

**Rationale:**
- Consistent language throughout the interface
- Easier maintenance and testing
- Accessible to international users

### JSON Handling (Critical)

**Use `printf '%s'` when piping shell variables to jq**

```bash
# BAD: echo interprets escape sequences (\n, \t) → JSON corruption
local title=$(echo "$issue" | jq -r '.title')

# GOOD: printf passes data as-is
local title=$(printf '%s' "$issue" | jq -r '.title')
```

Violating this rule causes jq parse errors on issues with newlines/tabs in description.

### Coprocess Pattern (FIFO-based)

**zsh `coproc` 사용 금지** - `read -sk1` 키 입력과 충돌. 대신 FIFO + fd 사용.

```bash
# BAD: coproc interferes with read -sk1
coproc python3 script.py
echo "cmd" >&p
read -r result <&p

# GOOD: explicit FIFOs with file descriptors
mkfifo "$_in_fifo" "$_out_fifo"
python3 script.py < "$_in_fifo" > "$_out_fifo" &
exec 7>"$_in_fifo" 8<"$_out_fifo"
echo "cmd" >&7
read -r result <&8
```

### Variable Declaration in Loops

**`local` 을 루프 안에서 재선언하면 현재 값이 stdout으로 출력됨**

```bash
# BAD: 2회차부터 _bc의 값이 stdout에 찍힘
while ...; do
  local _cc=${#_title} _bc
done

# GOOD: 루프 밖에서 선언, 안에서 할당만
local _cc _bc
while ...; do
  _cc=${#_title}
done
```

### EXIT Trap in Subshells

**`$(...)` 서브셸에서 EXIT trap 이 발동됨** - cleanup 함수에 가드 필요

```bash
cleanup() {
    [[ ${ZSH_SUBSHELL:-0} -gt 0 ]] && return
    # ... actual cleanup
}
```

### Parameter Flag Syntax

**`${(@f)var}` 에서 `$` 접두사 불필요**

```bash
# BAD: bad substitution error
${(@f)$_COPROC_RESULT}

# GOOD
${(@f)_COPROC_RESULT}
```

### Locale Handling (zsh-specific)

**`LC_ALL=C var=val` persists in zsh (unlike bash)**

```bash
# BAD: LC_ALL=C persists after this line, breaks subsequent ${#str}
LC_ALL=C byte_count=${#str}

# GOOD: Restore locale after use
LC_ALL=C byte_count=${#str}
unset LC_ALL
```

- 서브셸 `$(...)` 호출은 부모에 영향 없음
- 직접 호출 함수에서만 `unset LC_ALL` 필요

### ANSI Color in printf

**ANSI 코드는 format string 안에 넣어야 함**

```bash
# BAD: %s는 이스케이프 시퀀스를 해석하지 않음 → raw \033[2m 출력
printf "%s" "${A_DIM}text${A_RESET}"

# GOOD: format string에 직접 포함
printf "${A_DIM}%s${A_RESET}" "text"
```

### Terminal State for External Commands

**외부 명령(에디터, gum 등) 호출 전 터미널 상태 복원**

```bash
# stty -echo 상태에서 에디터 열면 입력 불가
stty echo 2>/dev/null   # 복원
$EDITOR "$file"
stty -echo 2>/dev/null  # 다시 비활성화
```

## Claude Code Integration

### Skills

The viban plugin provides two skills for automated issue management:

#### `/viban:assign`

Assigns the top backlog issue to the current session and executes the full resolution workflow:

1. Fetches the highest priority backlog issue
2. Assigns it to the current session
3. Analyzes the issue and executes the fix
4. Marks the issue as review/done upon completion

**Usage:**
```
/viban:assign
```

**When to use:**
- When you want Claude to autonomously pick and solve the next issue
- For continuous workflow in parallel sessions
- When issues are pre-prioritized in the backlog

#### `/viban:todo`

Analyzes a problem situation and creates a new viban issue with proper structure:

1. Analyzes the user's description
2. Creates a structured issue with:
   - Clear, concise title (Korean)
   - Detailed description with symptoms, root cause, and expected behavior
   - Appropriate priority (P0-P3)
   - Type tag (bug/feat/chore/etc)

**Usage:**
```
/viban:todo
```

Then describe the problem when prompted.

**When to use:**
- When you encounter a bug or want to track a new feature
- To convert free-form problem descriptions into structured issues
- Before starting work on a new problem

### CLI Commands

All CLI commands are available via the `viban` binary:

```bash
viban list              # Display kanban board
viban add "Title" "Desc" P2 feat  # Create issue
viban assign [session]  # Assign top backlog issue
viban review [id]       # Move issue to review
viban done <id>         # Mark issue as done (card stays on board)
viban done <id> --remove  # Delete card permanently
viban get <id>          # Get issue details (JSON)
viban help              # Show help
```

### Data Location

Issues are stored in `viban.json` in the `.viban/` directory:

```bash
# Default location
.viban/viban.json
```

**Custom location:**
```bash
export VIBAN_DATA_DIR="/path/to/data"
```

### Issue Status Flow

```
backlog → in_progress → review → done
            ↑              ↑
      (assign)       (complete)
```

### Parallel Sessions

Multiple Claude sessions can work in parallel:

1. Each session calls `/viban:assign`
2. Session ID is stored in `assigned_to`
3. Other sessions skip assigned issues
4. Completion moves issue to review/done

### Issue Structure

```json
{
  "version": 1,
  "issues": [
    {
      "id": 1,
      "title": "Issue title",
      "description": "Detailed description",
      "status": "backlog|in_progress|review|done",
      "priority": "P0|P1|P2|P3",
      "type": "bug|feat|chore|refactor|docs",
      "assigned_to": null | "session-id",
      "created_at": "2025-01-23T10:00:00Z",
      "updated_at": "2025-01-23T10:00:00Z"
    }
  ]
}
```

### Priority Levels

| Priority | Meaning |
|----------|---------|
| P0 | Critical - blocks all work |
| P1 | High - must do soon |
| P2 | Medium - normal priority |
| P3 | Low - nice to have |

### Type Tags

| Type | Use Case |
|------|----------|
| bug | Fixing broken functionality |
| feat | New feature or enhancement |
| refactor | Code restructuring |
| chore | Maintenance tasks |
| docs | Documentation updates |
| test | Test additions/fixes |
