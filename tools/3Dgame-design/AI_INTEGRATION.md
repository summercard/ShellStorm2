# AI Scene Editing Interface

SceneKit exposes a local, provider-neutral interface for AI agents. The server listens only on `127.0.0.1:4173`.

## Coordinate Contract

- Coordinate system: Blender `Z-up`
- Distance: meters (`m`)
- Rotation: degrees (`deg`)
- X: left/right, Y: depth, Z: height

## Read Scene Capabilities

`GET /api/ai/schema` returns the supported component types, coordinate contract, and available operations.

`GET /api/scenes` lists saved scenes. `GET /api/scenes/:sceneId` returns one complete scene document.

## Apply Commands

`POST /api/ai/scenes/:sceneId/commands`

```json
{
  "operations": [
    {
      "op": "add",
      "component": {
        "type": "办公桌",
        "name": "新增工位",
        "position": { "x": 2, "y": -3, "z": 0 },
        "rotation": { "x": 0, "y": 0, "z": 0 },
        "scale": { "x": 1, "y": 1, "z": 1 }
      }
    },
    {
      "op": "update",
      "name": "新增工位",
      "patch": {
        "position": { "x": 3, "y": -3, "z": 0 },
        "rotation": { "x": 0, "y": 0, "z": 90 }
      }
    },
    { "op": "remove", "name": "新增工位" }
  ]
}
```

The response contains the edited scene document. Reload that document in the preview to display the result. The in-app `AI 编辑` command window performs this request and reloads the preview automatically.
