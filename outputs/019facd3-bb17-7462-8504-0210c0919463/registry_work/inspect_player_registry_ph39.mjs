import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const registryPath =
  "/Users/summercards/ShellStorm2/assets/registry/ShellStorm2_美术资产台账_v001.xlsx";
const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(registryPath));
const sheetNames = ["资产主表", "分类与编码", "角色组件", "动画与状态", "命名与查重"];

for (const sheetName of sheetNames) {
  const sheet = workbook.worksheets.getItem(sheetName);
  const values = sheet.getUsedRange(true).values;
  const matching = [];
  for (let index = 0; index < values.length; index += 1) {
    const rowText = values[index].map((value) => String(value ?? "")).join(" | ");
    if (
      index === 0 ||
      /CHR-PLY-CAPSULE01|bunny01|玩家|角色|命名|查重|动画|状态|3D/.test(rowText)
    ) {
      matching.push({ row: index + 1, values: values[index] });
    }
  }
  console.log(JSON.stringify({ sheetName, matching }, null, 2));
}
