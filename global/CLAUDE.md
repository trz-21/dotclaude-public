# Global Instructions

## Verification Before Execution

When the user specifies requirements or constraints for an action, you MUST verify that all requirements are satisfied BEFORE proceeding:

1. **Dry-run mentally**: Before running a command, reason through exactly what it will do and what side effects it will have. Verify that the command's behavior matches all stated requirements.
2. **Test on one target first**: Never execute impactful commands across multiple targets at once. Run on a single target, verify the result meets all stated requirements with evidence (logs, status checks, etc.), then proceed to the rest.
3. **Verify, don't assume**: After each step, explicitly confirm that every requirement the user stated is satisfied. Do not assume success - check with actual evidence.
4. **If unsure, stop and ask**: If you cannot guarantee that a requirement will be met, stop and ask the user rather than proceeding optimistically.
5. **한 번에 성공하도록 설계**: 운영·인프라 작업은 실행 전에 선행 조건, 권한, 입력값 제약(예: 필드에 허용되는 문자), 순서 의존성을 미리 확인해서 재시도 없이 한 번에 끝나게 계획한다. 다단계 작업은 리허설(작은 대상)로 전 과정을 먼저 통과시킨다.
6. **즉시 롤백 가능한 계획만 실행**: 모든 변경은 실행 전에 되돌리는 방법(백업, 스냅샷, 이전 설정값, 되돌리기 명령)을 먼저 마련하고 확인한다. 실패 판단 기준과 롤백 절차를 계획에 함께 적고, 되돌릴 수 없는 단계는 따로 표시해 승인받는다.

## Git Worktree 격리

Git 레포의 코드를 수정하는 스킬은 **반드시 git worktree를 활용**하여 메인 작업 디렉토리와 격리된 공간에서 작업한다.
상세 절차는 `~/.claude/skills/_shared/git-worktree.md`를 참조한다.
단, 아래 dotclaude 레포는 예외로 직접 수정한다 (스킬 파일이 곧 레포 파일이고, 세션 종료 때 자동 커밋된다).

## ~/.claude 는 dotclaude 레포로 관리된다

`~/.claude`의 스킬·훅·설정·메모리·`me/`는 원본 레포 `~/.claude/dotclaude/source`(비공개)를 가리키는 심볼릭 링크다.
공개 레포 `~/.claude/dotclaude/export`는 원본에서 자동으로 만들어지는 가림 사본이라 직접 고치지 않는다.
구조와 셋업·동기화·아카이브·공개 방식은 원본 레포의 `CLAUDE.md`에 있다.

- 새 스킬·에이전트·커맨드는 `~/.claude/skills/` 등에 그냥 만들어도 세션 종료 때 원본 레포로 흡수된다.
- 공개하면 안 되는 이름을 새로 알게 되면 원본 레포 `blocklist.txt`에 추가한다. 문서 일부만 가리려면 `<!-- PRIVATE:START -->` / `<!-- PRIVATE:END -->`로 감싼다.
- 링크를 일반 파일로 바꾸거나 `~/.claude/dotclaude/` 링크를 지우지 않는다.

<!-- 이 구역은 개인 정보라 공개 사본에서 가렸습니다 -->
