# postgresql-haproxy 문서 인덱스

PostgreSQL 자동 failover(repmgr + HAProxy) PoC 의 설계·검증·운영 확장 문서 모음.

| 문서 | 내용 |
|---|---|
| [AUTOMATIC-FAILOVER.md](./AUTOMATIC-FAILOVER.md) | 자동 failover 동작화 패치 + 실측 로그 (repmgrd 기동, HTTP primary 헬스체크, 자동 재합류, 이중화 롤백) |
| [01-failover-rejoin-cycle.md](./01-failover-rejoin-cycle.md) | master 장애 → slave 승격 → 구 master 자동 재합류 전체 사이클 (실측) |
| [02-vip-vs-haproxy-port-routing.md](./02-vip-vs-haproxy-port-routing.md) | VIP 는 단일, read/write 는 HAProxy 포트(3000/3001)로 분리 |
| [03-failover-application-perspective.md](./03-failover-application-perspective.md) | failover 시 애플리케이션 관점 (짧은 중단 후 자동 재라우팅, read pool) |
| [04-spring-routing-datasource.md](./04-spring-routing-datasource.md) | Spring `AbstractRoutingDataSource` read/write 분리 (Spring Data JPA) |
| [05-production-vm-architecture.md](./05-production-vm-architecture.md) | 운영(VM 기반) 전체 논리/물리 구성도 |

## 읽는 순서 (추천)

1. **AUTOMATIC-FAILOVER.md** : 무엇을 고쳤고 어떻게 검증했는가 (배경/구조/실측)
2. **01** : 장애 → 승격 → 재합류 동작 원리
3. **02 → 03 → 04** : 애플리케이션 연동 (VIP/포트 → 앱 관점 → Spring 코드)
4. **05** : 운영(VM) 으로 확장할 때의 구성

상위: [../README.md](../README.md)
