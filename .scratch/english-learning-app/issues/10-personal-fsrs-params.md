# 10: 个人化 FSRS 参数

**What to build:** 复习记录攒够几百条后，GitHub Actions 用学习者自己的数据训练 FSRS 参数，写回私有仓库；App 同步到新参数后改用它调度，让复习间隔更贴合学习者的记忆。

- Actions 在 `english-data` 中用 py-fsrs 训练，只用来源为 review 的 Observation（不用测试和抽查）。复习条数低于门槛时跳过。
- 参数写入 `english-data` 的 FSRS 参数文件，保留权重和 decay，便于以后升级算法。
- App 同步时读取参数文件，存在就改用个人参数，否则继续用默认参数。

**Blocked by:** 06, 07

**Status:** ready-for-agent

- [ ] 复习条数不足门槛时，工作流跳过训练、不报错
- [ ] 用夹具复习记录训练出的参数文件格式正确，并能被 swift-fsrs 读入
- [ ] App 拿到个人参数后，同一张卡的下次间隔与用默认参数时不同，且与 swift-fsrs 用该参数的计算一致
- [ ] 训练只使用复习记录
