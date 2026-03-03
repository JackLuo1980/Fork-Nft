export interface NyImportItem {
  dest: string[];
  listen_port: number;
  name: string;
}

export interface ParsedNyImportLine {
  line: string;
  parsed?: NyImportItem;
  error?: string;
}

const ADDRESS_PATTERN = /^[^:]+:\d+$/;

const isValidListenPort = (value: unknown): value is number => {
  return (
    typeof value === "number" &&
    Number.isFinite(value) &&
    value >= 1 &&
    value <= 65535
  );
};

const validateNyItem = (line: string, value: unknown): ParsedNyImportLine => {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return { line, error: "JSON结构错误" };
  }

  const item = value as Record<string, unknown>;
  const dest = item.dest;
  const listenPort = item.listen_port;
  const name = item.name;

  if (!Array.isArray(dest) || dest.length === 0) {
    return { line, error: "dest数组为空或格式错误" };
  }

  if (typeof name !== "string" || name.trim() === "") {
    return { line, error: "name不能为空" };
  }

  if (!isValidListenPort(listenPort)) {
    return { line, error: "listen_port必须为1-65535之间的数字" };
  }

  const normalizedDest = dest.map((itemValue) =>
    typeof itemValue === "string" ? itemValue.trim() : "",
  );

  if (normalizedDest.some((itemValue) => itemValue === "")) {
    return { line, error: "dest中包含空地址" };
  }

  const invalid = normalizedDest.find(
    (itemValue) => !ADDRESS_PATTERN.test(itemValue),
  );

  if (invalid) {
    return { line, error: `目标地址格式错误: ${invalid}` };
  }

  return {
    line,
    parsed: {
      dest: normalizedDest,
      listen_port: listenPort,
      name: name.trim(),
    },
  };
};

const splitConcatenatedJsonObjects = (input: string): string[] => {
  const result: string[] = [];
  let depth = 0;
  let start = -1;
  let inString = false;
  let escaping = false;

  for (let i = 0; i < input.length; i += 1) {
    const char = input[i];

    if (escaping) {
      escaping = false;
      continue;
    }

    if (char === "\\") {
      escaping = true;
      continue;
    }

    if (char === '"') {
      inString = !inString;
      continue;
    }

    if (inString) {
      continue;
    }

    if (char === "{") {
      if (depth === 0) {
        start = i;
      }
      depth += 1;
      continue;
    }

    if (char === "}") {
      depth -= 1;
      if (depth === 0 && start >= 0) {
        result.push(input.slice(start, i + 1));
        start = -1;
      }
    }
  }

  return result;
};

export const parseNyFormatData = (input: string): ParsedNyImportLine[] => {
  const trimmed = input.trim();

  if (!trimmed) {
    return [];
  }

  const parsedResults: ParsedNyImportLine[] = [];
  const objectChunks = splitConcatenatedJsonObjects(trimmed);

  if (objectChunks.length > 0) {
    objectChunks.forEach((chunk) => {
      try {
        const parsed = JSON.parse(chunk);

        parsedResults.push(validateNyItem(chunk, parsed));
      } catch {
        parsedResults.push({ line: chunk, error: "JSON解析失败" });
      }
    });

    return parsedResults;
  }

  trimmed
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line !== "")
    .forEach((line) => {
      try {
        const parsed = JSON.parse(line);

        parsedResults.push(validateNyItem(line, parsed));
      } catch {
        parsedResults.push({ line, error: "JSON解析失败" });
      }
    });

  return parsedResults;
};

export const convertNyItemToForwardInput = (item: NyImportItem) => {
  return {
    name: item.name.trim(),
    inPort: item.listen_port,
    remoteAddr: item.dest.join(","),
    strategy: "fifo" as const,
  };
};
