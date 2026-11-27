// System introspection and live Lua 5.4 execution tools.

export const SYSTEM_TOOLS = [
  {
    name: "moho_status",
    rpcMethod: "moho.status",
    description: "Check live Moho Pro 14.4 connectivity, plugin version, active document, active layer, frame, active action, Layer Comp count, and exporter path.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "moho_activatePoller",
    rpcMethod: null,
    hostHandler: "activatePoller",
    description: "Locate the custom MohoStudioMCP Poller teal-star icon in Moho Pro 14.4's toolbar via PrintWindow and click it in the background (PostMessage) without moving the user's mouse cursor or stealing window focus. Also runs automatically if any live RPC stalls for >1.1s.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "moho_apiInspect",
    rpcMethod: "moho.apiInspect",
    description: "Inspect live Lua 5.4 classes, methods, tolua++ .get/.set properties, and constants exposed by Moho 14.4 (e.g. MOHO, LM, moho, document, layer, M_Bone, M_Mesh).",
    inputSchema: {
      type: "object",
      properties: {
        target: { type: "string", description: "Global or MOHO/LM class name (default: 'MOHO')" },
        filter: { type: "string", description: "Optional case-insensitive substring filter" },
        limit: { type: "number", description: "Maximum entries to return (default: 250)" },
      },
    },
  },
  {
    name: "lua_execute",
    rpcMethod: "lua.execute",
    timeoutKind: "lua",
    description: "Execute Lua 5.4 code live inside Moho Pro 14.4 with `moho`, `helpers`, `json`, `delaunay`, and `args` in scope. Guarded by pcall + optional PrepMultiUndo and captures print() logs.",
    inputSchema: {
      type: "object",
      required: ["code"],
      properties: {
        code: { type: "string", description: "Lua 5.4 chunk to execute; `return <value>` sends JSON back" },
        args: { type: "object", description: "Optional JSON object exposed as `args` inside the chunk" },
        undo: { type: "boolean", description: "Wrap in PrepMultiUndo before running (default: true)" },
      },
    },
  },
];
