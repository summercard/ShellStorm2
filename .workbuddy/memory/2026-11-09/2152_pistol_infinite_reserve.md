# 2026-11-09 21:52 豌豆手枪改判：弹匣 10 发 + 备弹无限

- **业主原话**：「豌豆手枪应该是弹夹保持 10 发，打完后备弹无限。」→ 21:12 那版「弹匣无限（开火不扣弹）」作废。
- **落地**：`magazine_size 12 → 10`；`infinite_ammo` 删除、新增 `infinite_reserve_ammo = true`。开火**恢复扣弹**（早先两处豁免删掉），弹匣照常打空、换弹照常 1.4 s，只是换弹不扣备弹。
- **HUD 纠正**：当前弹数恢复真实值，只有备弹段显示 `∞`。早先连当前弹数都显示 `∞` —— 弹匣真会空，那是骗人。
- **节奏**：4.35 s 打空 + 1.4 s 换弹 = 周期 5.75 s，换弹占 24.3% 是长期 DPS 唯一上限（弹药总量不再是上限）。
- **验收**：`STARTING_WEAPON_CONTRACT_OK`（10 发）/ `GUARANTEED_LOADOUT_AMMO_OK` / `FINITE_AMMO_FLOW_OK` / `3D_RELOAD_STATE_FLOW_OK` / `HUD_PRESENTER_3D_OK` / `verify_opening_script_runtime_OK checks=126`，全 exit 0。
- **门禁写法**：四组判据全部**反过来**写（开火必须扣 1、空匣必须被拒且自动起换弹、无备弹连打两轮、HUD 弹数真实 + `∞备弹`），防的是「有人改回弹匣无限」。
- 记录：`docs/v0.1/development/2026-11-09_pistol_infinite_reserve_ammo.md`
