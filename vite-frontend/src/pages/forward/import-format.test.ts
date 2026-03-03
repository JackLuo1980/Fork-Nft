import test from "node:test";
import assert from "node:assert/strict";

import {
  convertNyItemToForwardInput,
  parseNyFormatData,
} from "./import-format.ts";

test("parseNyFormatData parses concatenated ny JSON objects", () => {
  const input =
    '{"dest":["151.241.129.52:23609"],"listen_port":20224,"name":"灵玥-JP-Lpt【三网通用】"}{"dest":["64.81.33.2:24577"],"listen_port":41034,"name":"Yolo-US-Lpt【三网通用】"}';

  const result = parseNyFormatData(input);

  assert.equal(result.length, 2);
  assert.equal(result[0].error, undefined);
  assert.equal(result[1].error, undefined);
  assert.deepEqual(result[0].parsed?.dest, ["151.241.129.52:23609"]);
  assert.equal(result[0].parsed?.listen_port, 20224);
  assert.equal(result[1].parsed?.name, "Yolo-US-Lpt【三网通用】");
});

test("parseNyFormatData parses newline-separated ny JSON objects", () => {
  const input = [
    '{"dest":["1.1.1.1:1000","2.2.2.2:2000"],"listen_port":3000,"name":"A"}',
    '{"dest":["3.3.3.3:4000"],"listen_port":5000,"name":"B"}',
  ].join("\n");

  const result = parseNyFormatData(input);

  assert.equal(result.length, 2);
  assert.equal(result[0].error, undefined);
  assert.equal(result[1].error, undefined);
  assert.deepEqual(result[0].parsed?.dest, ["1.1.1.1:1000", "2.2.2.2:2000"]);
  assert.equal(result[0].parsed?.listen_port, 3000);
});

test("parseNyFormatData returns validation errors for invalid fields", () => {
  const input =
    '{"dest":[],"listen_port":0,"name":""}{"dest":["bad-address"],"listen_port":80,"name":"ok"}';

  const result = parseNyFormatData(input);

  assert.equal(result.length, 2);
  assert.match(result[0].error || "", /dest数组为空|listen_port|name/);
  assert.match(result[1].error || "", /目标地址格式错误/);
});

test("convertNyItemToForwardInput maps ny fields correctly", () => {
  const mapped = convertNyItemToForwardInput({
    dest: ["1.1.1.1:1111", "2.2.2.2:2222"],
    listen_port: 3333,
    name: "  Forward Name  ",
  });

  assert.deepEqual(mapped, {
    name: "Forward Name",
    inPort: 3333,
    remoteAddr: "1.1.1.1:1111,2.2.2.2:2222",
    strategy: "fifo",
  });
});
