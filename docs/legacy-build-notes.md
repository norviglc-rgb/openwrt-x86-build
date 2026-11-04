# 旧仓库迁移说明

旧版工作流默认拉取 LEDE/master，追加未固定的第三方 feed，包含 Docker、PassWall、默认管理密码及多个写死的接口/防火墙配置，并自动发布固件与删除历史。这不符合现在“官方 25.12.6 / OpenClash / J4125 / 最小依赖 / 有凭据隔离”的目标。

本分支的新工作流完全不再调用旧版 scripts/diy-part1.sh、scripts/diy-part2.sh，不读取旧 settings.ini、feeds.conf 或 config/x86-64.config。

旧配置文件已从当前分支删除，保留在 Git 历史供审计比较。无法再作为运行的构建配置。
