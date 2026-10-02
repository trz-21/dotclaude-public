---
name: subagent 적극 활용
description: 작업 시 subagent를 적극적으로 활용해야 함
type: feedback
---

작업할 때 subagent를 적극적으로 활용한다.

**Why:** 사용자가 명시적으로 요청함. 병렬 작업, 컨텍스트 보호, 복잡한 멀티스텝 작업에 subagent를 활용하는 것을 선호.

**How to apply:** 코드 수정, 탐색, 검증 등 분리 가능한 작업은 subagent로 위임. 단순 파일 읽기/편집은 직접 처리해도 무방하나, 복잡한 구현이나 검증은 subagent 활용.
