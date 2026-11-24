import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { MohoIpcClient, escapePsSingleQuoted, buildCaptureWindowPs } from "../src/ipc.mjs";

async function run() {
  const tempIpc = fs.mkdtempSync(path.join(os.tmpdir(), "moho-studio-ipc-test-"));
  const statusPath = path.join(tempIpc, "status.json");
  fs.writeFileSync(
    statusPath,
    JSON.stringify({ running: true, name: "moho-studio-mcp", version: "1.0.0" }),
    "utf8"
  );

  // Mock Moho Lua polling loop processing concurrent UUID requests
  let handled = 0;
  const mockPoller = setInterval(() => {
    const files = fs.readdirSync(tempIpc).filter((f) => f.startsWith("req_") && f.endsWith(".json"));
    for (const fname of files) {
      const reqPath = path.join(tempIpc, fname);
      let raw;
      try {
        raw = fs.readFileSync(reqPath, "utf8");
        fs.unlinkSync(reqPath);
      } catch {
        continue;
      }
      const req = JSON.parse(raw);
      const reqId = fname.slice(4, -5);
      const respPath = path.join(tempIpc, `resp_${reqId}.json`);
      const respTmp = `${respPath}.tmp`;
      let resp;
      if (req.method === "fail.test") {
        resp = { jsonrpc: "2.0", id: req.id, error: { code: -32603, message: "simulated lua failure" } };
      } else {
        resp = { jsonrpc: "2.0", id: req.id, result: { echoedMethod: req.method, seq: req.params.seq, client: req.params.client } };
      }
      fs.writeFileSync(respTmp, JSON.stringify(resp), "utf8");
      fs.renameSync(respTmp, respPath);
      handled += 1;
    }
  }, 15);

  const clientA = new MohoIpcClient(tempIpc);
  const clientB = new MohoIpcClient(tempIpc);
  // Disable Windows PowerShell keep-alive spawn during unit test
  clientA.startKeepAlive = () => {};
  clientB.startKeepAlive = () => {};

  try {
    // Fire 12 concurrent requests from 2 simultaneous clients (simulating Codex + Antigravity!)
    const promises = [];
    for (let i = 0; i < 6; i += 1) {
      promises.push(clientA.send("moho.status", { client: "antigravity", seq: i }, 4000));
      promises.push(clientB.send("document.getInfo", { client: "codex", seq: i }, 4000));
    }
    const results = await Promise.all(promises);
    assert.equal(results.length, 12);
    assert.equal(handled, 12);
    for (let i = 0; i < 6; i += 1) {
      assert.equal(results[i * 2].client, "antigravity");
      assert.equal(results[i * 2].seq, i);
      assert.equal(results[i * 2 + 1].client, "codex");
      assert.equal(results[i * 2 + 1].seq, i);
    }

    // Verify error propagation
    await assert.rejects(
      () => clientA.send("fail.test", {}, 4000),
      /simulated lua failure/
    );

    // Verify missing status.json gives actionable error
    fs.unlinkSync(statusPath);
    await assert.rejects(
      () => clientA.send("moho.status", {}, 1000),
      /MohoStudioMCP Server is not active/
    );

    // Verify PowerShell single-quote escaping in captureWindow script builder
    const trickyPath = "C:\\Users\\O'Brien\\My $Project\\cap`1 \"test\".png";
    assert.equal(escapePsSingleQuoted("a'b'c"), "a''b''c");
    const capPs = buildCaptureWindowPs(trickyPath);
    assert.ok(
      capPs.includes("$bmp.Save('C:\\Users\\O''Brien\\My $Project\\cap`1 \"test\".png', [System.Drawing.Imaging.ImageFormat]::Png)"),
      "captureWindow PS script should single-quote path with doubled apostrophes"
    );
    assert.ok(!capPs.includes('$bmp.Save("'), "captureWindow PS script must not use double-quoted path interpolation");

    console.log("PASS test_ipc_mock: 12 concurrent dual-client UUID requests + PS escaping + error/offline checks OK");
  } finally {
    clearInterval(mockPoller);
    clientA.stopKeepAlive();
    clientB.stopKeepAlive();
    fs.rmSync(tempIpc, { recursive: true, force: true });
  }
}

run().catch((err) => {
  console.error("FAIL test_ipc_mock:", err);
  process.exit(1);
});
