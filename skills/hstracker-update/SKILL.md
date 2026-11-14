---
name: hstracker-update
description: 맥 HSTracker 커스텀 빌드(종족 버그 수정, 세션 패널 독립 창, 상대 MMR 호버)를 새 공식 버전에 맞춰 다시 만들어 설치한다. "HSTracker가 업데이트됐어", "HSTracker 새 버전 나왔어", "HSTracker 업데이트 알림 떴어", "HSTracker 그 작업 해줘", "HSTracker 공식 앱으로 덮어써졌어", "HSTracker 다시 설치했어", "HSTracker 자동 업데이트 실패 알림", "하스 트래커 업데이트됐나?" 같은 말에 사용한다. HSTracker 커스텀 빌드 상태 확인이나 Bob's Buddy 종족 버그 재발 문의에도 사용한다.
---

# HSTracker 커스텀 빌드 업데이트

`/Applications/HSTracker.app`은 공식 앱이 아니라 수정을 넣어 직접 만든 앱이다(임시 서명). 공식 업데이트나 재설치는 이 앱을 덮어써서 수정이 모두 사라진다. 수정 내용은 다음과 같다.

1. 종족 버그 수정. 맥 HSTracker(3.1.10~)가 Power.log의 CARDRACE 이름값을 0으로 파싱해 Bob's Buddy의 모든 하수인 종족이 INVALID가 되고, 현신(크툰·이샤라즈)이 시뮬에서 안 깨어나 오예측이 난다.
2. 세션 패널 독립 창(맥북 주 모니터 오른쪽 위). 사용자 요구: 세션 패널은 게임 화면을 전혀 가리면 안 된다.
3. 엔진에 넘기는 종족 값 로그(`pBoardRaces=[...]`). 전부 0이면 종족 버그가 돌아온 것이다.
4. 상대 MMR 표시(HDT_BGrank 이식). 상대 초상화 호버 때만 뜬다.

**정본은 `~/HSTracker-backup/README.md`다.** 절차·경로·버전별 특이사항은 이 스킬에 다시 적지 않는다. 작업을 시작하기 전에 README 맨 위 절("3.7.2부터 소스가 공개되지 않는다")을 먼저 읽고 그대로 따른다.

## 1. 상태 점검

```
/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' -c 'Print CFBundleVersion' /Applications/HSTracker.app/Contents/Info.plist
grep -m2 "Starting HSTracker\|Loaded BobsBuddy" ~/Library/Logs/HSTracker/hstracker.log
curl -s https://api.github.com/repos/HearthSim/HSTracker-Releases/releases/latest | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['tag_name'],d['published_at'])"
tail -5 ~/Library/Logs/HSTracker/auto-update/auto-update.log
pgrep -lf "Sparkle|Updater"
ls ~/Library/Caches/net.hearthsim.hstracker/org.sparkle-project.Sparkle/Installation/
```

- 버전은 `defaults read`로 보지 않는다. Info.plist를 캐시해서 공식 앱으로 덮어써진 뒤에도 옛 커스텀 번호를 보여 준 적이 있다(2026-11-14). 로그의 마지막 `Starting HSTracker` 줄도 함께 본다.
- 커스텀 빌드인지: `CFBundleVersion`이 `<공식 빌드 번호>.1`처럼 `.1`로 끝나고, 로그 첫 줄이 `Starting HSTracker/<버전>.<빌드>.1`이면 커스텀이다. `.1`이 없으면 공식 앱으로 덮어써진 것이다.
- 최신 버전은 `HearthSim/HSTracker-Releases`에서 본다(3.7.2부터 `HearthSim/HSTracker` 소스와 릴리스는 비공개).
- 2026-11-14부터 `auto-update.sh`가 아래 2절을 자동으로 한다. 업데이트 버튼을 누르면 Sparkle이 공식 앱을 깔고, launchd가 Info.plist 변경을 보고 1분 안에 커스텀 앱으로 되돌린다. 그러니 사용자가 "업데이트됐어"라고 하면 먼저 auto-update 로그에 `done: <버전>`이 있는지 보고, 있으면 결과만 확인해 알린다(손으로 다시 할 필요 없음). 아직 안 돌았으면 `~/HSTracker-backup/auto-update.sh`를 직접 한 번 실행한다. `GAVE UP`이 있으면 그 실행 폴더(`run-<버전>-<시각>/`)의 로그로 원인을 보고 2절을 손으로 진행한 뒤 `auto-update.sh --force`로 마무리한다.
- 설치된 커스텀 버전과 최신 릴리스가 같으면 할 일이 없다고 알리고 끝낸다.

- 먼저 `~/HSTracker-backup/.auto-update/paused`가 있는지 본다. 있으면 사용자가 공식 앱을 일부러 쓰는 중이다(2026-11-14에 한 번 시험했다가 같은 날 되돌림. 공식 앱은 세션 패널을 창 밖에 둘 수 없고 MMR 호버가 없어서 사용자가 커스텀을 골랐다). 이때는 커스텀으로 바꾸지 말고, 공식 앱 업데이트는 Sparkle에 맡긴다. 사용자가 커스텀으로 돌아가자고 하면 `rm ~/HSTracker-backup/.auto-update/paused && ~/HSTracker-backup/auto-update.sh --force`를 실행한다.

## 2. 새 버전 적용 (DLL 교체 방식, 요약)

자동 업데이트가 실패했을 때 손으로 하는 순서다. `auto-update.sh` 코드가 같은 순서를 그대로 구현하고 있으니 막힌 단계를 거기서 찾는다. 세부는 README 맨 위 절을 따른다.

1. 새 공식 앱 zip을 `HSTracker-Releases` 릴리스에서 받아 빈 작업 폴더(스크래치패드)에 풀고 `codesign --verify --deep --strict`로 공식 서명을 확인한다. Sparkle이 이미 풀어 둔 사본이 있어도 직접 받은 것을 쓴다.
2. `~/HSTracker-backup/HSTracker-official-<버전>.app`으로 순정 백업한다.
3. `Contents/Resources/Resources/Managed/`의 `BobsBuddy.dll`·`BobsBuddy.Common.dll`·`HearthDb.dll`을 직전 공식 버전 백업과 해시로 비교한다. Managed 폴더의 다른 파일도 바뀌었는지 본다(바뀐 게 많으면 사용자에게 알린다).
4. `HSTracker-custom-3.7.1.app` 사본에 바뀐 DLL을 덮어쓴다. `CFBundleVersion`을 `<새 공식 빌드 번호>.1`로 바꾼다.
5. `build-custom.sh` 끝부분처럼 `disable-library-validation` 권한을 넣어 `codesign --force --options runtime --entitlements ... -s -`로 다시 서명한다.
6. **Sparkle 대기 설치를 먼저 없앤다(아래 함정 참고).**
7. HSTracker를 끄고 교체 설치한 뒤 켠다. 직전 앱은 되돌릴 수 있게 남겨 둔다.
8. 확인: 로그에 `Starting HSTracker/<버전>.<새 빌드>.1`, `Loaded BobsBuddy version <새 엔진 버전>`이 찍히고 앱이 꺼지지 않는다. 켜자마자 꺼지거나 Bob's Buddy 에러가 나면 HearthDb만 이전 것으로 돌려 보고, 그래도 안 되면 직전 앱으로 되돌린다.
9. README 맨 위 버전 줄(현재 앱 설명, 빌드 번호, 로그 첫 줄 예시), "이 폴더의 파일" 목록(새 `HSTracker-official-<버전>.app`, `BobsBuddy.dll.orig-<버전>` 등), 버전별 특이사항을 갱신한다. 원본 엔진은 `BobsBuddy.dll.orig-<버전>`으로 백업해 둔다.
10. 사용자에게 다음 전장 판에서 볼 것을 알린다: 로그의 `pBoardRaces`(전부 0이면 안 됨), 세션 패널 위치, 상대 MMR 호버(`BGrank: loaded`, `BGrank: lobby`).

## 함정: Sparkle이 이미 받아 둔 업데이트

사용자가 업데이트 알림에서 설치를 눌렀거나 Sparkle이 미리 받아 둔 경우, 새 공식 앱이 `~/Library/Caches/net.hearthsim.hstracker/org.sparkle-project.Sparkle/Installation/`에 풀려 있고 `Autoupdate`·`Updater` 프로세스가 대기한다. 이 상태로 HSTracker를 끄면 그 순간 공식 앱으로 덮어쓴다. 커스텀 앱을 설치하기 전에 반드시 다음을 한다.

```
pgrep -lf "Sparkle|Updater"      # Autoupdate, Updater.app 확인
pkill -f "Sparkle.framework/Versions/B/Autoupdate"; pkill -f "org.sparkle-project.Sparkle/Launcher"
rm -rf ~/Library/Caches/net.hearthsim.hstracker/org.sparkle-project.Sparkle/Installation/*
pgrep -lf "Sparkle|Updater" || echo clean
```

그다음 HSTracker를 끄고 설치한다. 설치 후 `CFBundleVersion`이 `.1`로 끝나는지 다시 확인한다.

## 진행 규칙

- HSTracker는 게임 중이어도 묻지 않고 바로 껐다 켠다. 사용자가 두 번 직접 허락했고, 기다리느라 늦어지는 쪽을 더 싫어한다. 하스스톤 자체를 끄는 것은 해당하지 않는다.
- 공식 레포에 PR이나 이슈를 올리지 않는다(사용자가 올리지 말라고 했다).
- 소스가 다시 공개되면 README의 "새 버전이 나왔을 때" 절차와 옛 스크립트 `auto-update.sh.bak-build-20261114`를 쓴다.
- 손으로 고친 방법이 다음에도 통할 만하면 `auto-update.sh`에도 반영하고, 반영 전에 `--force`로 리허설한다.
- 앱 안 Sparkle 자동 설치는 `SUAutomaticallyUpdate=false`로 꺼 두었다. 새 빌드 번호를 공식보다 높게(`.1`) 두는 이유는 Sparkle이 같은 버전을 다시 권하지 않게 하려는 것이다.
