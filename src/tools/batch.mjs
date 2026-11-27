// Atomic multi-operation batch execution tool.

export const BATCH_TOOLS = [
  {
    name: "batch_execute",
    rpcMethod: "batch.execute",
    timeoutKind: "batch",
    description: "Execute up to 100 Moho Studio MCP operations atomically inside one IPC round-trip, one Undo step, and one coalesced UI refresh.",
    inputSchema: {
      type: "object",
      required: ["operations"],
      properties: {
        stopOnError: { type: "boolean", description: "Abort remaining ops on first failure (default: true)" },
        operations: {
          type: "array",
          description: "Ordered list of { method, params } RPC calls to execute",
          items: {
            type: "object",
            required: ["method"],
            properties: {
              method: { type: "string", description: "RPC method name (e.g. 'bone.create', 'bone.setDynamics', 'layer.setProperties')" },
              params: { type: "object", description: "Arguments matching the target tool schema" },
            },
          },
        },
      },
    },
  },
];
