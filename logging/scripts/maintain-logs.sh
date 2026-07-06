#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# Jepangku — Log Maintenance Script (Phase 6.3)
# ═══════════════════════════════════════════════════════════════════
#
# Usage:
#   ./maintain-logs.sh              # dry-run (info only)
#   ./maintain-logs.sh --prune      # prune expired log data
#   ./maintain-logs.sh --backup     # backup Loki data directory
#   ./maintain-logs.sh --status     # check disk usage
#   ./maintain-logs.sh --all        # status + prune + backup
#
# Requirements: docker compose, rsync (for backup)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGGING_DIR="$(dirname "$SCRIPT_DIR")"
LOKI_DATA_VOLUME="jepangku-infra_loki-data"
BACKUP_DIR="${LOGGING_DIR}/backups"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# ─── Colors ───────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ─── Help ──────────────────────────────────────────────────────────
show_help() {
  cat <<EOF
Jepangku — Log Maintenance Script

Usage:
  $0 [OPTION]

Options:
  --prune      Run Loki compactor to prune expired log data (retention 7 hari)
  --backup     Backup Loki data directory to ./backups/
  --status     Check disk usage of Docker volumes
  --all        Run: status → prune → backup
  --help       Show this message

Without options: dry-run (show info only)
EOF
  exit 0
}

# ─── Status ────────────────────────────────────────────────────────
check_status() {
  echo ""
  info "═══════════════ Disk Usage ═══════════════"
  echo ""

  # Docker disk usage
  info "Docker system disk usage:"
  docker system df 2>/dev/null || warn "Docker not running"

  echo ""

  # Volume sizes
  info "Loki data volume size:"
  docker run --rm -v ${LOKI_DATA_VOLUME}:/data alpine du -sh /data 2>/dev/null \
    || warn "Cannot access Loki volume (container may not be running)"

  echo ""

  # Compactor status (via Loki ready endpoint)
  info "Loki readiness:"
  curl -sf http://localhost:3100/ready 2>/dev/null \
    && ok "Loki is ready" \
    || warn "Loki not reachable on :3100"

  echo ""

  # Log retention config
  info "Retention period: 168h (7 hari)"
  info "Compactor enabled: true"

  echo ""
}

# ─── Prune ─────────────────────────────────────────────────────────
prune_logs() {
  echo ""
  info "═══════════════ Pruning Expired Logs ═══════════════"
  echo ""

  # Trigger compactor via Loki HTTP endpoint
  # The compactor runs automatically based on config, but we can trigger it
  info "Compactor berjalan otomatis tiap 10 menit (default Loki)."
  info "Untuk memaksa kompaksi, restart Loki:"
  echo "  docker compose -f ${LOGGING_DIR}/docker-compose.logging.yml restart loki"
  echo ""

  # Prune Docker system (unused resources)
  info "Menghapus resource Docker yang tidak dipakai..."
  docker system prune -f --volumes=false 2>/dev/null \
    && ok "Docker system prune selesai" \
    || warn "Docker prune gagal (mungkin tidak ada akses)"

  echo ""
}

# ─── Backup ────────────────────────────────────────────────────────
backup_data() {
  echo ""
  info "═══════════════ Backup Loki Data ═══════════════"
  echo ""

  mkdir -p "${BACKUP_DIR}"
  local backup_path="${BACKUP_DIR}/loki-data-${TIMESTAMP}.tar.gz"

  info "Membackup volume ${LOKI_DATA_VOLUME} ke ${backup_path}..."

  # Backup with docker volume
  docker run --rm \
    -v ${LOKI_DATA_VOLUME}:/data \
    -v "${BACKUP_DIR}:/backup" \
    alpine \
    tar czf "/backup/loki-data-${TIMESTAMP}.tar.gz" -C /data . 2>/dev/null \
    && ok "Backup berhasil: ${backup_path}" \
    || error "Backup gagal"

  # Show backup size
  if [ -f "${backup_path}" ]; then
    local size=$(du -h "${backup_path}" | cut -f1)
    info "Ukuran backup: ${size}"

    # Cleanup backups older than 30 days
    info "Menghapus backup > 30 hari..."
    find "${BACKUP_DIR}" -name "loki-data-*.tar.gz" -mtime +30 -delete 2>/dev/null \
      && ok "Backup lama dihapus" \
      || true
  fi

  echo ""
}

# ─── Main ──────────────────────────────────────────────────────────
main() {
  local cmd="${1:-}"

  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║     Jepangku — Log Maintenance                  ║${NC}"
  echo -e "${BLUE}║     $(date '+%Y-%m-%d %H:%M:%S WIB')             ║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"

  case "$cmd" in
    --prune)
      prune_logs
      ok "Prune selesai"
      ;;
    --backup)
      backup_data
      ok "Backup selesai"
      ;;
    --status)
      check_status
      ok "Status check selesai"
      ;;
    --all)
      check_status
      prune_logs
      backup_data
      ok "Semua maintenance selesai"
      ;;
    --help|-h)
      show_help
      ;;
    *)
      info "Dry-run mode. Gunakan salah satu opsi berikut:"
      info "  $0 --status    → cek penggunaan disk"
      info "  $0 --prune     → pruning log expired"
      info "  $0 --backup    → backup data Loki"
      info "  $0 --all       → semua langkah di atas"
      info "  $0 --help      → bantuan"
      echo ""
      check_status
      ;;
  esac
}

main "$@"
