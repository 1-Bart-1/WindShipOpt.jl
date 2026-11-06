/**
 * A node of a recording exported by the Julia model: an input with its base value, a
 * constant, or an operation on earlier nodes, by their index from zero.
 */
export type RecordedNode =
  | ["input", string, number]
  | ["constant", number]
  | [string, number]
  | [string, number, number];

const binary: Record<string, (a: number, b: number) => number> = {
  "+": (a, b) => a + b,
  "-": (a, b) => a - b,
  "*": (a, b) => a * b,
  "/": (a, b) => a / b,
  "^": Math.pow,
  min: Math.min,
  max: Math.max,
};

const unary: Record<string, (a: number) => number> = {
  "-": (a) => -a,
  sqrt: Math.sqrt,
  exp: Math.exp,
  log: Math.log,
};

/**
 * Value of every node of `nodes` with each input at its value in `inputs`, or at its base
 * value where `inputs` does not name it.
 */
export function evaluate(nodes: RecordedNode[], inputs: Record<string, number>): Float64Array {
  const values = new Float64Array(nodes.length);
  nodes.forEach((node, k) => {
    const [operation, a, b] = node;
    if (operation === "input") values[k] = inputs[a as string] ?? (b as number);
    else if (operation === "constant") values[k] = a as number;
    else if (node.length === 3) values[k] = binary[operation](values[a as number], values[b as number]);
    else values[k] = unary[operation](values[a as number]);
  });
  return values;
}
