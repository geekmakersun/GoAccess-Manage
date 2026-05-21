#!/bin/bash
# ================================================================================
# 脚本名称：更新GeoLite2.sh
# 功能描述：更新免费版 GeoLite2 地理位置数据库
# 适用环境：宝塔面板 + CentOS/Rocky/AlmaLinux/Debian/Ubuntu/Windows Git Bash
# 创建日期：2026-05-20
# 更新日期：2026-05-21
#
# 设计思路：
# 1. 使用"原子更新"策略：先下载到临时文件，验证成功后再替换
# 2. 自动备份旧版本（带时间戳）
# 3. 支持重试机制，网络不稳定也能成功
# 4. 验证下载的文件大小，防止下载到错误文件
# 5. 检查磁盘空间，防止下载一半失败
# 6. 版本判断：自动检测并下载最新版本
# 7. 跨平台支持：兼容 Windows Git Bash 和 Linux 系统
# ================================================================================

# 开启严格错误处理模式
set -eo pipefail

# Windows Git Bash 环境下添加工具路径
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    export PATH="/c/Program Files/Git/usr/bin:$PATH"
fi

# ================================================================================
# 常量定义区域（使用 readonly 确保常量不可修改）
# ================================================================================
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly GEOIP_DIR="$SCRIPT_DIR"
readonly GEOIP_CITY_DB="$GEOIP_DIR/GeoLite2-City.mmdb"
readonly GEOIP_ASN_DB="$GEOIP_DIR/GeoLite2-ASN.mmdb"
readonly GEOIP_VERSION_FILE="$GEOIP_DIR/GeoIP.version"
readonly GEOIP_CITY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"
readonly GEOIP_ASN_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb"
readonly GEOIP_MIRROR_URLS=(
    "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"
    "https://cdn.jsdelivr.net/gh/P3TERX/GeoLite.mmdb@download/GeoLite2-City.mmdb"
    "https://fastly.jsdelivr.net/gh/P3TERX/GeoLite.mmdb@download/GeoLite2-ASN.mmdb"
)
readonly TIMEOUT=120
readonly MAX_RETRIES=3
readonly MIN_DISK_SPACE_MB=100
readonly MIN_FILE_SIZE=1000000

# ================================================================================
# ANSI 颜色代码定义（用于美化输出）
# ================================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# ================================================================================
# 全局变量
# ================================================================================
IS_WINDOWS=false
DOWNLOAD_TOOL=""

# ================================================================================
# 工具函数库
# ================================================================================

print_separator() {
    echo -e "${BLUE}============================================================${NC}"
}

print_title() {
    print_separator
    echo -e "${GREEN}$1${NC}"
    print_separator
    echo ""
}

log_info() {
    echo -e "${YELLOW}[INFO] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

log_error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    fi
    return 1
}

detect_os() {
    log_info "检测操作系统..."
    
    if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        IS_WINDOWS=true
        log_info "检测到 Windows 系统 (Git Bash)"
    else
        IS_WINDOWS=false
        log_info "检测到 Linux/Unix 系统"
    fi
    
    if check_command wget; then
        DOWNLOAD_TOOL="wget"
        log_success "使用 wget 进行下载"
    elif check_command curl; then
        DOWNLOAD_TOOL="curl"
        log_success "使用 curl 进行下载"
    else
        log_error "未找到 wget 或 curl 工具"
        return 1
    fi
}

check_disk_space() {
    local required_mb=$1
    
    if [ "$IS_WINDOWS" = true ]; then
        local available_mb=$(df -m "$GEOIP_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
    else
        local available_mb=$(df -m "$GEOIP_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
    fi
    
    if [ -z "$available_mb" ]; then
        available_mb=$(df -m /tmp | awk 'NR==2 {print $4}')
    fi
    
    if [ "$available_mb" -lt "$required_mb" ]; then
        log_error "磁盘空间不足，需要 ${required_mb}MB，可用 ${available_mb}MB"
        return 1
    fi
    
    log_success "磁盘空间充足: ${available_mb}MB"
    return 0
}

get_file_size() {
    local file=$1
    if [ -f "$file" ]; then
        if [ "$IS_WINDOWS" = true ]; then
            stat -c%s "$file" 2>/dev/null || wc -c < "$file" | awk '{print $1}'
        else
            stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null
        fi
    else
        echo "0"
    fi
}

get_file_date() {
    local file=$1
    if [ -f "$file" ]; then
        if [ "$IS_WINDOWS" = true ]; then
            # Windows Git Bash: 使用 stat -c%Y 或直接获取文件修改时间
            local timestamp=$(stat -c%Y "$file" 2>/dev/null || echo "0")
            if [ "$timestamp" = "0" ]; then
                # 如果 stat 不支持，尝试使用 PowerShell 命令
                timestamp=$(powershell.exe -Command "(Get-Item '$file').LastWriteTime.ToFileTimeUtc()" 2>/dev/null || echo "0")
            fi
            echo "$timestamp"
        else
            # Linux: 使用 stat -c%Y 或 stat -f%m
            stat -c%Y "$file" 2>/dev/null || stat -f%m "$file" 2>/dev/null || echo "0"
        fi
    else
        echo "0"
    fi
}

download_file() {
    local url=$1
    local output=$2
    local attempt=1
    
    while [ $attempt -le $MAX_RETRIES ]; do
        log_info "下载尝试 ${attempt}/${MAX_RETRIES}..."
        
        if [ "$DOWNLOAD_TOOL" = "wget" ]; then
            if wget --timeout="$TIMEOUT" --tries=3 --waitretry=5 -q -O "$output" "$url" 2>/dev/null; then
                return 0
            fi
        elif [ "$DOWNLOAD_TOOL" = "curl" ]; then
            if curl -L --connect-timeout "$TIMEOUT" --max-time 300 -s -o "$output" "$url" 2>/dev/null; then
                return 0
            fi
        fi
        
        log_warning "下载失败，等待重试..."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    return 1
}

download_with_mirrors() {
    local output=$1
    local db_type=$2
    
    log_info "开始下载 GeoLite2-${db_type} 数据库..."
    
    for url in "${GEOIP_MIRROR_URLS[@]}"; do
        if [[ "$url" == *"$db_type"* ]]; then
            log_info "尝试镜像源: $url"
            
            if download_file "$url" "$output"; then
                local file_size=$(get_file_size "$output")
                if [ "$file_size" -gt "$MIN_FILE_SIZE" ]; then
                    log_success "下载成功，文件大小: $((file_size / 1024 / 1024)) MB"
                    return 0
                else
                    log_warning "下载的文件过小 ($file_size bytes)，尝试下一个镜像源"
                    rm -f "$output"
                fi
            fi
        fi
    done
    
    return 1
}

read_version_file() {
    if [ -f "$GEOIP_VERSION_FILE" ]; then
        source "$GEOIP_VERSION_FILE"
    fi
}

write_version_file() {
    local city_version=$1
    local city_date=$2
    local city_size=$3
    local asn_version=$4
    local asn_date=$5
    local asn_size=$6
    
    cat > "$GEOIP_VERSION_FILE" << EOF
# GeoIP 数据库版本信息
# 此文件由更新脚本自动生成，请勿手动修改

# GeoLite2-City 数据库信息
CITY_VERSION="$city_version"
CITY_DATE="$city_date"
CITY_SIZE="$city_size"
CITY_UPDATE_TIME="$(date '+%Y-%m-%d %H:%M:%S')"

# GeoLite2-ASN 数据库信息
ASN_VERSION="$asn_version"
ASN_DATE="$asn_date"
ASN_SIZE="$asn_size"
ASN_UPDATE_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
EOF
    
    chmod 644 "$GEOIP_VERSION_FILE"
}

get_database_info() {
    local db_file=$1
    local db_type=$2
    
    if [ ! -f "$db_file" ]; then
        echo ""
        return 1
    fi
    
    local file_size=$(get_file_size "$db_file")
    local file_date=$(get_file_date "$db_file")
    local file_date_str=$(date -d "@$file_date" '+%Y-%m-%d' 2>/dev/null || date -r "$file_date" '+%Y-%m-%d' 2>/dev/null || echo "Unknown")
    
    echo "${db_type}|${file_date_str}|${file_size}"
}

show_version_info() {
    read_version_file
    
    echo ""
    echo -e "${BLUE}GeoIP 数据库版本信息:${NC}"
    echo "========================================"
    
    if [ -n "$CITY_VERSION" ]; then
        echo -e "${GREEN}GeoLite2-City:${NC}"
        echo "  版本: $CITY_VERSION"
        echo "  日期: $CITY_DATE"
        echo "  大小: $CITY_SIZE bytes"
        echo "  更新时间: $CITY_UPDATE_TIME"
    else
        echo -e "${YELLOW}GeoLite2-City: 未安装${NC}"
    fi
    
    echo ""
    
    if [ -n "$ASN_VERSION" ]; then
        echo -e "${GREEN}GeoLite2-ASN:${NC}"
        echo "  版本: $ASN_VERSION"
        echo "  日期: $ASN_DATE"
        echo "  大小: $ASN_SIZE bytes"
        echo "  更新时间: $ASN_UPDATE_TIME"
    else
        echo -e "${YELLOW}GeoLite2-ASN: 未安装${NC}"
    fi
    
    echo "========================================"
    echo ""
}

check_database_version() {
    local db_file=$1
    local db_type=$2
    
    if [ ! -f "$db_file" ]; then
        log_info "未找到 GeoLite2-${db_type} 数据库文件"
        return 1
    fi
    
    local file_date=$(get_file_date "$db_file")
    local current_date=$(date +%s)
    local age_days=$(( (current_date - file_date) / 86400 ))
    
    log_info "GeoLite2-${db_type} 数据库年龄: ${age_days} 天"
    
    if [ "$age_days" -gt 30 ]; then
        log_warning "数据库已超过 30 天，建议更新"
        return 1
    else
        log_success "数据库较新，无需更新"
        return 0
    fi
}

atomic_update() {
    local new_file=$1
    local old_file=$2
    local backup_file="${old_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [ -f "$old_file" ]; then
        log_info "备份当前数据库到: $backup_file"
        if ! cp "$old_file" "$backup_file"; then
            log_error "备份失败"
            return 1
        fi
    fi
    
    log_info "验证下载的文件..."
    if [ ! -s "$new_file" ]; then
        log_error "下载的文件为空或大小为 0"
        rm -f "$new_file"
        return 1
    fi
    
    local file_size=$(get_file_size "$new_file")
    if [ "$file_size" -lt "$MIN_FILE_SIZE" ]; then
        log_error "文件大小异常: ${file_size} bytes，可能下载失败"
        rm -f "$new_file"
        return 1
    fi
    
    log_info "移动新文件到目标位置..."
    if ! mv "$new_file" "$old_file"; then
        log_error "移动文件失败"
        return 1
    fi
    
    log_success "原子更新完成"
    return 0
}

update_database() {
    local db_type=$1
    local db_file=$2
    local temp_file="${db_file}.tmp.$(date +%s)"
    
    print_title "更新 GeoLite2-${db_type}"
    
    if check_database_version "$db_file" "$db_type"; then
        log_info "跳过更新（数据库较新）"
        return 0
    fi
    
    log_info "下载地址: $GEOIP_CITY_URL"
    
    if [ -f "$db_file" ]; then
        local current_size=$(get_file_size "$db_file")
        log_info "当前数据库大小: ${current_size} bytes"
    fi
    
    if download_with_mirrors "$temp_file" "$db_type"; then
        log_success "下载完成"
    else
        log_error "下载失败，已尝试所有镜像源"
        rm -f "$temp_file"
        return 1
    fi
    
    log_info "执行原子更新..."
    if atomic_update "$temp_file" "$db_file"; then
        echo ""
        print_title "更新完成！"
        
        log_success "GeoLite2-${db_type} 数据库已成功更新！"
        echo ""
        
        if [ -f "$db_file" ]; then
            local new_size=$(get_file_size "$db_file")
            local new_date=$(date -d "@$(get_file_date "$db_file")" '+%Y-%m-%d' 2>/dev/null || date -r "$(get_file_date "$db_file")" '+%Y-%m-%d' 2>/dev/null || echo "Unknown")
            echo -e "  ${BLUE}版本日期:${NC} ${new_date}"
            echo -e "  ${BLUE}文件大小:${NC} ${new_size} bytes"
            echo -e "  ${BLUE}文件位置:${NC} $db_file"
            
            update_version_file "$db_type" "$new_date" "$new_size"
        fi
        
        echo ""
        return 0
    else
        log_error "更新失败"
        return 1
    fi
}

update_version_file() {
    local db_type=$1
    local db_date=$2
    local db_size=$3
    
    read_version_file
    
    if [ "$db_type" = "City" ]; then
        CITY_VERSION="GeoLite2-${db_type}"
        CITY_DATE="$db_date"
        CITY_SIZE="$db_size"
    elif [ "$db_type" = "ASN" ]; then
        ASN_VERSION="GeoLite2-${db_type}"
        ASN_DATE="$db_date"
        ASN_SIZE="$db_size"
    fi
    
    write_version_file "${CITY_VERSION:-}" "${CITY_DATE:-}" "${CITY_SIZE:-}" "${ASN_VERSION:-}" "${ASN_DATE:-}" "${ASN_SIZE:-}"
    
    log_success "版本信息已更新到: $GEOIP_VERSION_FILE"
}

cleanup_old_backups() {
    log_info "清理旧的备份文件..."
    
    local backup_count=0
    for backup_file in "$GEOIP_DIR"/*.backup.*; do
        if [ -f "$backup_file" ]; then
            local file_date=$(echo "$backup_file" | grep -oE '[0-9]{8}_[0-9]{6}')
            if [ -n "$file_date" ]; then
                local backup_age=$(( ($(date +%s) - $(date -d "${file_date:0:4}-${file_date:4:2}-${file_date:6:2} ${file_date:9:2}:${file_date:11:2}:${file_date:13:2}" +%s 2>/dev/null || echo "0")) / 86400 ))
                if [ "$backup_age" -gt 7 ]; then
                    rm -f "$backup_file"
                    backup_count=$((backup_count + 1))
                fi
            fi
        fi
    done
    
    if [ "$backup_count" -gt 0 ]; then
        log_success "已清理 $backup_count 个超过 7 天的备份文件"
    else
        log_info "没有需要清理的备份文件"
    fi
}

show_usage() {
    echo "用法: $SCRIPT_NAME [选项]"
    echo ""
    echo "选项:"
    echo "  -c, --city         更新 GeoLite2-City 数据库"
    echo "  -a, --asn          更新 GeoLite2-ASN 数据库"
    echo "  -f, --force        强制更新，忽略版本检查"
    echo "  -v, --version      显示数据库版本信息"
    echo "  -C, --clean        清理旧的备份文件"
    echo "  -h, --help         显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $SCRIPT_NAME              # 更新所有数据库"
    echo "  $SCRIPT_NAME -c           # 只更新 City 数据库"
    echo "  $SCRIPT_NAME -f           # 强制更新所有数据库"
    echo "  $SCRIPT_NAME -v           # 显示版本信息"
    echo "  $SCRIPT_NAME -C           # 清理备份文件"
}

# ================================================================================
# 主程序开始
# ================================================================================

print_title "GeoLite2 数据库更新脚本 v2.0"

log_info "脚本目录: $SCRIPT_DIR"
log_info "GeoIP 目录: $GEOIP_DIR"
echo ""

UPDATE_CITY=true
UPDATE_ASN=true
FORCE_UPDATE=false
CLEAN_BACKUPS=false
SHOW_VERSION=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--city)
            UPDATE_CITY=true
            UPDATE_ASN=false
            shift
            ;;
        -a|--asn)
            UPDATE_CITY=false
            UPDATE_ASN=true
            shift
            ;;
        -f|--force)
            FORCE_UPDATE=true
            shift
            ;;
        -v|--version)
            SHOW_VERSION=true
            shift
            ;;
        -C|--clean)
            CLEAN_BACKUPS=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            log_error "未知选项: $1"
            show_usage
            exit 1
            ;;
    esac
done

detect_os
echo ""

log_info "检查磁盘空间..."
check_disk_space "$MIN_DISK_SPACE_MB"
echo ""

show_version_info

if [ "$CLEAN_BACKUPS" = true ]; then
    cleanup_old_backups
    exit 0
fi

if [ "$UPDATE_CITY" = true ]; then
    if [ "$FORCE_UPDATE" = true ]; then
        rm -f "$GEOIP_CITY_DB"
    fi
    update_database "City" "$GEOIP_CITY_DB"
fi

if [ "$UPDATE_ASN" = true ]; then
    if [ "$FORCE_UPDATE" = true ]; then
        rm -f "$GEOIP_ASN_DB"
    fi
    update_database "ASN" "$GEOIP_ASN_DB"
fi

cleanup_old_backups
show_version_info

echo ""
echo -e "${CYAN}下一步：${NC}"
echo "1. 运行 ../分析所有站点.sh 生成新的访问报告"
echo "2. 或在宝塔面板设置定时任务自动更新（每周二）"
echo ""
