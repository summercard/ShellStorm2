# 2026-11-10 事务索引

- [1052 敌方子弹回退 3D 弹体，公告板保留且缩到 70%](1052_enemy_bullet_presentation_rollback.md)：业主澄清 11-09 只要求「判定体积 = 放大后模型体积」，公告板降级为可选（`ENEMY_BULLET_BILLBOARD=false`，单发 `projectile_config["billboard"]` 可覆盖）。图标核心由「== 判定球直径」改成 ×0.70，语义降级为「所见小于所中」，判定球不动。`verify_crosshair_billboard` 31→37 samples 全绿，另加三条缺省哨兵防止总开关被悄悄改回。**遗留**：公告板「看着大」是外晕 1.67 倍核心 + 描边不足 1px，不是尺寸倍率。**方法论**：查「什么时候改的」先看文件 mtime —— 这类改动常常只在每日自动提交里出现一次，git log 断不出时间点。
