# Chart: pixnest-postgres

In-cluster PostgreSQL for pixnest: a hardened single-replica **StatefulSet** (non-root uid
999, read-only rootfs, dropped capabilities, pinned `postgres:16.15`) with a
PersistentVolumeClaim, a headless Service at the fixed name `pixnest-postgres`, its
credentials Secret, and a NetworkPolicy allowing only the backend chart's pods on 5432.

The backend chart connects using its `database` values, which must match `auth` here
(cross-chart convention; production moves both to a real secret store).

| Values file | Use |
|-------------|-----|
| `values.yaml` | Base: image pin, demo auth, 5Gi volume. |
| `values-eks.yaml` | EKS: 20Gi EBS-backed volume. |

Trade-off: an in-cluster DB means you own backups, HA, and upgrades. The
production-grade paths are the CloudNativePG operator or managed RDS/Aurora.

