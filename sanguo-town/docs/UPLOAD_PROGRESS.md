# 分批上传记录

## 交付规则

不再将大量开发成果集中到最后一次上传。按一个依赖完整的小模块拆分；源码、对应测试和模块说明尽量同批提交。尚未满足独立构建条件的成果先放到checkpoints，不影响可运行版本。每批完成真实分支提交后回读文件或Git树确认；main只接收已完成集成验证的版本。

## 第一批：长期养城核心源码检查点

日期：2026-09-20。

保存目录：`checkpoints/town-0.4-core/`。

已保存：RealmDevelopment.swift、RealmRuntime.swift、GrowthRuntime.swift，共79,502字节。具体Git blob SHA见该目录README。

状态：**远端源码检查点；不是town-0.4完整集成或Mac开发包。** 当前Sources、Tests和Package.swift保持原样；现有可运行版本不被这批未齐全的依赖破坏。

待后续批次：核心模型与校验的配套更改；城景表现与Mac界面；对应测试；长周期和原生构建结果；最终集成。

提交编号以本文件Git历史为准，不在提交内部自嵌尚未生成的commit SHA。不要把源码已保存、模块编译通过、全量回归通过和main已合并混为一个状态。
