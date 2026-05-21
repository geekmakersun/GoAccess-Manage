# GeoIP 数据库目录

本目录用于存放 GeoIP 数据库文件，用于 GoAccess 的地理位置分析功能。

## 📦 需要的数据库文件

- `GeoLite2-City.mmdb` - 城市地理位置数据库
- `GeoLite2-ASN.mmdb` - 自治系统号数据库（可选）

## 📥 自动更新（推荐）

### 使用更新脚本

本目录包含自动更新脚本 `更新GeoLite2.sh`，支持自动检测和更新数据库。

#### 基本用法

```bash
# 更新所有数据库（自动检测版本，超过30天才更新）
./更新GeoLite2.sh

# 只更新 City 数据库
./更新GeoLite2.sh -c

# 只更新 ASN 数据库
./更新GeoLite2.sh -a

# 强制更新（忽略版本检查）
./更新GeoLite2.sh -f

# 清理旧的备份文件
./更新GeoLite2.sh -C
```

#### 跨平台支持

脚本支持以下环境：
- ✅ Linux（CentOS/Ubuntu/Debian 等）
- ✅ Windows Git Bash
- ✅ macOS

#### 自动更新特性

- **版本检测**：自动检测数据库年龄，超过 30 天才更新
- **多镜像源**：支持 GitHub、jsDelivr、Fastly CDN 多个镜像源
- **原子更新**：先下载到临时文件，验证成功后再替换
- **自动备份**：更新前自动备份旧版本
- **清理机制**：自动清理超过 7 天的备份文件

## 📥 手动下载

### 方式 1：从 MaxMind 官网下载

1. 注册 MaxMind 账号：https://www.maxmind.com/en/geolite2/signup
2. 登录后访问：https://www.maxmind.com/en/accounts/current/geoip/downloads
3. 下载 `GeoLite2 City` 和 `GeoLite2 ASN`（MMDB 格式）
4. 解压后将 `.mmdb` 文件放到本目录

### 方式 2：使用 geoipupdate 工具

```bash
# 安装 geoipupdate
sudo apt-get install geoipupdate  # Debian/Ubuntu
sudo yum install geoipupdate      # CentOS/RHEL

# 配置账号信息
sudo nano /etc/GeoIP.conf

# 更新数据库
sudo geoipupdate
```

### 方式 3：从镜像源手动下载

```bash
# 下载 GeoLite2-City
wget -O GeoLite2-City.mmdb https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb

# 或使用 jsDelivr CDN
wget -O GeoLite2-City.mmdb https://cdn.jsdelivr.net/gh/P3TERX/GeoLite.mmdb@download/GeoLite2-City.mmdb

# 下载 GeoLite2-ASN
wget -O GeoLite2-ASN.mmdb https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb
```

## 🔄 更新频率

MaxMind 每周二更新 GeoLite2 数据库，建议定期更新以获得准确的地理位置数据。

## ⚙️ 定时任务设置

### 宝塔面板定时任务

在宝塔面板添加计划任务：

```bash
# 每周二凌晨 3 点自动更新
0 3 * * 2 cd /www/wwwroot/GoAccess-管理/GeoIP && ./更新GeoLite2.sh >> /var/log/geoip-update.log 2>&1
```

### Linux Crontab

```bash
# 编辑 crontab
crontab -e

# 添加定时任务（每周二凌晨 3 点）
0 3 * * 2 cd /www/wwwroot/GoAccess-管理/GeoIP && ./更新GeoLite2.sh
```

## 📝 注意事项

- GeoLite2 是 MaxMind 提供的免费数据库，精度略低于付费版本
- 数据库文件较大（约 60-70 MB），请确保有足够的磁盘空间
- 如果不使用地理位置功能，可以不下载这些数据库文件
- 更新脚本会自动清理超过 7 天的备份文件
